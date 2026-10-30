//
//  HistoryListTableView.swift
//  SixOne
//
//  历史记录列表的容器与行宿主：虚拟化、单元格复用、环境注入、选中镜像与滚动命令。
//

import AppKit
import SwiftUI

/// 列表滚动几何：把「行 + 上下留白」最小限度地滚进视口，两端由文档边界钳住。
enum HistoryListScrollGeometry {
    static func targetOriginY(
        paddedRow: CGRect,
        visible: CGRect,
        documentHeight: CGFloat
    ) -> CGFloat {
        let maxY = max(0, documentHeight - visible.height)
        if paddedRow.minY < visible.minY {
            return min(max(0, paddedRow.minY), maxY)
        }
        if paddedRow.maxY > visible.maxY {
            return min(maxY, max(0, paddedRow.maxY - visible.height))
        }
        return visible.minY
    }
}

struct HistoryListTableView: NSViewRepresentable {
    let context: PanelContext
    let rows: [HistoryRow]
    /// 行数据版本，用于触发比对；必须与 `rows` 同源，否则表格会停在旧顺序。
    let dataRevision: Int
    let locale: Locale
    let selectedItemID: UUID?
    var isSelectionActive = false
    /// 让 SwiftUI 在选中没变、只多了滚动命令时也更新一轮。
    let scrollRevision: Int
    /// 确认弹窗压着时停掉用户滚动（程序化滚动不受影响）。
    var isScrollBlocked = false
    /// 按住 ⌘ 时的快速粘贴编号范围；nil 表示不显示编号。
    var quickPasteRange: ClosedRange<Int>? = nil

    let onSelect: (UUID) -> Void
    let onActivate: (UUID, Bool) -> Void
    let onCopy: (UUID) -> Void
    let menuProvider: (HistoryRow, RowInteractionHost.HostView) -> NSMenu?
    var onVisibleRowRangeChanged: ((ClosedRange<Int>) -> Void)?
    var onScrollerLayoutChanged: ((Bool) -> Void)?
    var beep: () -> Void = { NSSound.beep() }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onVisibleRowRangeChanged: onVisibleRowRangeChanged,
            onScrollerLayoutChanged: onScrollerLayoutChanged
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, tableView) = ListTableScaffold.make(
            columnIdentifier: Coordinator.columnIdentifier
        )
        scrollView.isScrollBlocked = isScrollBlocked
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        context.coordinator.tableView = tableView
        context.coordinator.apply(self)
        context.coordinator.observe(scrollView)
        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView else { return }
            context.coordinator.performInitialLayout(in: scrollView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView,
              let listScrollView = scrollView as? ListScrollView else { return }
        listScrollView.isScrollBlocked = isScrollBlocked
        // 更新期间由 reload/滚动触发的发布排到下一轮，避免写回 body 正在读的状态。
        context.coordinator.isInViewUpdate = true
        defer { context.coordinator.isInViewUpdate = false }

        let coordinator = context.coordinator
        coordinator.onVisibleRowRangeChanged = onVisibleRowRangeChanged
        coordinator.onScrollerLayoutChanged = onScrollerLayoutChanged
        coordinator.apply(self)

        if coordinator.needsScrollerLayoutPublish(for: scrollView) {
            DispatchQueue.main.async { [weak scrollView] in
                guard let scrollView else { return }
                coordinator.publishScrollerLayout(for: scrollView)
            }
        }

        if coordinator.syncRows(with: self, in: tableView) {
            coordinator.pinDocumentHeight(tableView, in: scrollView)
            // 过滤后行数变短不会产生边界通知，排一轮重算可见范围。
            DispatchQueue.main.async {
                context.coordinator.publishVisibleRowRange()
            }
        }

        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = 0
            animation.allowsImplicitAnimation = false
            coordinator.syncSelectionAppearance(in: tableView)
            coordinator.syncQuickPasteHints(in: tableView)
            coordinator.syncSelection(in: tableView)
            coordinator.handle(
                self.context.navigationState.takePendingScrollCommands(),
                in: tableView,
                of: listScrollView
            )
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.removeObservers()
    }

    final class Coordinator: ListTableCoordinator {
        static let columnIdentifier = NSUserInterfaceItemIdentifier("SixOneHistoryRow")
        static let cellIdentifier = NSUserInterfaceItemIdentifier("SixOneHistoryRowCell")
        static let rowViewIdentifier = NSUserInterfaceItemIdentifier("SixOneHistoryRowView")

        private var rows: [HistoryRow] = []
        private var makeRow: ((HistoryRow, Int, CGFloat, CGFloat) -> AnyView)?
        private var selectedItemID: UUID?
        private var isSelectionActive = false
        private var quickPasteRange: ClosedRange<Int>?

        private var reloadedDataRevision: Int?
        private var reloadedLocale: Locale?
        private var reloadedRowCount = -1
        private var mirroredSelectionID: UUID?
        private struct RenderedSelection: Equatable {
            var id: UUID?
            var isActive: Bool
        }
        private var renderedSelection = RenderedSelection(id: nil, isActive: false)
        private var renderedQuickPasteRange: ClosedRange<Int>?
        private var beep: () -> Void = { NSSound.beep() }

        override init(
            onVisibleRowRangeChanged: ((ClosedRange<Int>) -> Void)?,
            onScrollerLayoutChanged: ((Bool) -> Void)?
        ) {
            super.init(
                onVisibleRowRangeChanged: onVisibleRowRangeChanged,
                onScrollerLayoutChanged: onScrollerLayoutChanged
            )
            observesScrollerStyle = true
        }

        // MARK: - 行数据

        override var rowCount: Int { rows.count }
        override var rowViewIdentifier: NSUserInterfaceItemIdentifier { Self.rowViewIdentifier }
        override var cellIdentifier: NSUserInterfaceItemIdentifier { Self.cellIdentifier }

        override func topPadding(row: Int) -> CGFloat {
            row == 0 ? ClipboardLayout.verticalPadding : 0
        }

        override func bottomPadding(row: Int) -> CGFloat {
            row == rows.count - 1 ? ClipboardLayout.verticalPadding : 0
        }

        override func makeRowContent(at index: Int, topPadding: CGFloat, bottomPadding: CGFloat) -> AnyView {
            guard rows.indices.contains(index), let makeRow else { return AnyView(Color.clear) }
            return makeRow(rows[index], index, topPadding, bottomPadding)
        }

        /// 收下本轮落点与回调；行视图在这里拼好，环境逐行注入。
        func apply(_ parent: HistoryListTableView) {
            selectedItemID = parent.selectedItemID
            isSelectionActive = parent.isSelectionActive
            quickPasteRange = parent.quickPasteRange
            beep = parent.beep
            rowClickTracker.onSelect = parent.onSelect
            rowClickTracker.onActivate = parent.onActivate
            let tracker = rowClickTracker
            let selectedID = parent.selectedItemID
            let selectionActive = parent.isSelectionActive
            let quickPasteRange = parent.quickPasteRange
            makeRow = { [context = parent.context, locale = parent.locale] row, index, topPadding, bottomPadding in
                AnyView(
                    ClipboardRowView(
                        row: row,
                        shortcutNumber: QuickPaste.shortcutNumber(forRow: index, in: quickPasteRange),
                        isSelected: row.id == selectedID,
                        isListActive: selectionActive,
                        listTopPadding: topPadding,
                        listBottomPadding: bottomPadding,
                        onSelect: { parent.onSelect($0) },
                        // 激活目标由行宿主按连击序列起点给 id，不是当前行。
                        onActivate: { parent.onActivate($0, $1) },
                        onCopy: { parent.onCopy(row.id) },
                        menuProvider: { anchor in parent.menuProvider(row, anchor) },
                        clickTracker: tracker
                    )
                    .environment(context)
                    .environment(\.locale, locale)
                )
            }
        }

        /// 把本轮行数据同步进表格，返回是否整表重建；同 id 只原位刷新内容。
        @discardableResult
        func syncRows(with parent: HistoryListTableView, in tableView: NSTableView) -> Bool {
            let localeChanged = reloadedLocale != parent.locale
            let countChanged = reloadedRowCount != parent.rows.count
            guard localeChanged || countChanged || reloadedDataRevision != parent.dataRevision else {
                return false
            }

            let newRows = parent.rows
            reloadedDataRevision = parent.dataRevision
            reloadedRowCount = newRows.count
            reloadedLocale = parent.locale

            let idsChanged = rows.count != newRows.count
                || zip(rows, newRows).contains { pair in pair.0.id != pair.1.id }
            guard localeChanged || idsChanged else {
                let oldRows = rows
                rows = newRows
                for (index, pair) in zip(oldRows, newRows).enumerated() where pair.0 != pair.1 {
                    refreshRowContent(at: index, in: tableView)
                }
                return false
            }

            rows = newRows
            mirroredSelectionID = nil
            tableView.reloadData()
            renderedSelection = RenderedSelection(id: selectedItemID, isActive: isSelectionActive)
            return true
        }

        // MARK: - 选中外观

        /// 只刷新选中状态真正变化的那两行；行内观察全局选中会让每次点击重算整屏。
        func syncSelectionAppearance(in tableView: NSTableView) {
            let current = RenderedSelection(id: selectedItemID, isActive: isSelectionActive)
            guard current != renderedSelection else { return }
            let previous = renderedSelection
            renderedSelection = current
            for id in Set([previous.id, current.id].compactMap { $0 }) {
                guard let index = rows.firstIndex(where: { $0.id == id }) else { continue }
                refreshRowContent(at: index, in: tableView)
            }
        }

        /// 编号出现/消失或随滚动重排时，只刷新涉及到的行。
        func syncQuickPasteHints(in tableView: NSTableView) {
            guard quickPasteRange != renderedQuickPasteRange else { return }
            let previous = renderedQuickPasteRange
            renderedQuickPasteRange = quickPasteRange
            var indices: Set<Int> = []
            for range in [previous, quickPasteRange].compactMap({ $0 }) {
                indices.formUnion(range)
            }
            for index in indices.sorted() where rows.indices.contains(index) {
                refreshRowContent(at: index, in: tableView)
            }
        }

        // MARK: - 选中镜像

        /// 把模型选中单向同步到表格，表格不回写。
        func syncSelection(in tableView: NSTableView) {
            guard let selectedItemID else {
                guard mirroredSelectionID != nil else { return }
                mirroredSelectionID = nil
                tableView.deselectAll(nil)
                return
            }
            guard mirroredSelectionID != selectedItemID,
                  let index = rows.firstIndex(where: { $0.id == selectedItemID }) else { return }
            mirroredSelectionID = selectedItemID
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }

        // MARK: - 滚动

        func handle(
            _ commands: [HistoryListScrollCommand],
            in tableView: NSTableView,
            of scrollView: ListScrollView
        ) {
            guard !commands.isEmpty else { return }
            for (offset, command) in commands.enumerated() {
                handle(
                    command,
                    isLast: offset == commands.count - 1,
                    in: tableView,
                    of: scrollView
                )
            }
        }

        private func handle(
            _ command: HistoryListScrollCommand,
            isLast: Bool,
            in tableView: NSTableView,
            of scrollView: ListScrollView
        ) {
            guard !rows.isEmpty else { return }

            let index: Int
            switch command.target {
            case .row(let id):
                guard let found = rows.firstIndex(where: { $0.id == id }) else { return }
                index = found
            case .top:
                index = 0
            }

            // 滚「行 + 留白」，让被切掉的一侧也留出呼吸空间。
            let visible = scrollView.contentView.bounds
            guard visible.height > 0 else { return }
            let paddedRect = tableView.rect(ofRow: index)
                .insetBy(dx: 0, dy: -ClipboardLayout.verticalPadding)
            let targetY = HistoryListScrollGeometry.targetOriginY(
                paddedRow: paddedRect,
                visible: visible,
                documentHeight: tableView.frame.height
            )
            if scrollView.scrollViewport(toY: targetY) {
                return
            }
            guard command.isEndpointJump else { return }
            // 无位移不点亮滚动条；仅端点空操作且是最后一条命令时响一声。
            if command.isSelectionAlreadyAtEndpoint, isLast {
                beep()
            }
        }

        // MARK: - 点击

        /// 窗口级左键兜底；正常路径收口后追踪器已清空，不会重复落点。
        override func handleClickMonitor(_ event: NSEvent) {
            guard let tableView, event.window === tableView.window else { return }
            switch event.type {
            case .leftMouseDown:
                rowClickTracker.cancel()
            case .leftMouseUp:
                guard let pressed = rowClickTracker.pressedRowID else { return }
                guard let index = rows.firstIndex(where: { $0.id == pressed }) else {
                    rowClickTracker.cancel()
                    return
                }
                // 按按下那一条的当前矩形判定是否拖出；行被应用滚走不算。
                let point = tableView.convert(event.locationInWindow, from: nil)
                rowClickTracker.end(
                    event: event,
                    releaseInsideRow: tableView.rect(ofRow: index).contains(point)
                )
            default:
                break
            }
        }
    }
}
