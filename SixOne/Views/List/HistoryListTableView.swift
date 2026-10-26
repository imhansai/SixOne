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

    let onSelect: (UUID) -> Void
    let onActivate: (UUID) -> Void
    let onCopy: (UUID) -> Void
    let menuProvider: (HistoryRow, RowInteractionHost.HostView) -> NSMenu?
    var onTopVisibleRowChanged: ((Int) -> Void)?
    var onScrollerLayoutChanged: ((Bool) -> Void)?
    var beep: () -> Void = { NSSound.beep() }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTopVisibleRowChanged: onTopVisibleRowChanged,
            onScrollerLayoutChanged: onScrollerLayoutChanged
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ListScrollView()
        scrollView.isScrollBlocked = isScrollBlocked
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.hasVerticalScroller = true
        // 不设 contentInsets：它会把可滚动范围往两端撑开。
        scrollView.automaticallyAdjustsContentInsets = false

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.intercellSpacing = .zero
        tableView.rowHeight = ClipboardLayout.rowHeight
        tableView.usesAutomaticRowHeights = false
        tableView.style = .plain
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.autoresizingMask = [.width]
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        let column = NSTableColumn(identifier: Coordinator.columnIdentifier)
        column.resizingMask = .autoresizingMask
        column.width = ClipboardLayout.panelWidth
        column.minWidth = 120
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.contentView.postsFrameChangedNotifications = true
        context.coordinator.tableView = tableView
        context.coordinator.apply(self)
        context.coordinator.observe(scrollView)
        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView else { return }
            context.coordinator.publishTopVisibleRow()
            context.coordinator.publishScrollerLayout(for: scrollView)
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
        coordinator.onTopVisibleRowChanged = onTopVisibleRowChanged
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
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            coordinator.syncSelectionAppearance(in: tableView)
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

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let columnIdentifier = NSUserInterfaceItemIdentifier("SixOneHistoryRow")
        static let cellIdentifier = NSUserInterfaceItemIdentifier("SixOneHistoryRowCell")
        static let rowViewIdentifier = NSUserInterfaceItemIdentifier("SixOneHistoryRowView")

        var onTopVisibleRowChanged: ((Int) -> Void)?
        var onScrollerLayoutChanged: ((Bool) -> Void)?
        var isInViewUpdate = false
        weak var tableView: NSTableView?

        private var rows: [HistoryRow] = []
        private var makeRow: ((HistoryRow, CGFloat, CGFloat) -> AnyView)?
        private var selectedItemID: UUID?
        private var isSelectionActive = false
        let rowClickTracker = RowClickTracker()

        private var reloadedDataRevision: Int?
        private var reloadedLocale: Locale?
        private var reloadedRowCount = -1
        private var mirroredSelectionID: UUID?
        private struct RenderedSelection: Equatable {
            var id: UUID?
            var isActive: Bool
        }
        private var renderedSelection = RenderedSelection(id: nil, isActive: false)
        private var beep: () -> Void = { NSSound.beep() }

        private var lastPublishedTopVisibleRow: Int?
        private var lastPublishedUsesOverlayScrollers: Bool?
        private var boundsObserver: NSObjectProtocol?
        private var frameObserver: NSObjectProtocol?
        private var styleObserver: NSObjectProtocol?
        private var clickMonitor: Any?

        init(
            onTopVisibleRowChanged: ((Int) -> Void)?,
            onScrollerLayoutChanged: ((Bool) -> Void)?
        ) {
            self.onTopVisibleRowChanged = onTopVisibleRowChanged
            self.onScrollerLayoutChanged = onScrollerLayoutChanged
        }

        // MARK: - 装载

        /// 收下本轮落点与回调；行视图在这里拼好，环境逐行注入。
        func apply(_ parent: HistoryListTableView) {
            selectedItemID = parent.selectedItemID
            isSelectionActive = parent.isSelectionActive
            beep = parent.beep
            rowClickTracker.onSelect = parent.onSelect
            rowClickTracker.onActivate = parent.onActivate
            let tracker = rowClickTracker
            let selectedID = parent.selectedItemID
            let selectionActive = parent.isSelectionActive
            makeRow = { [context = parent.context, locale = parent.locale] row, topPadding, bottomPadding in
                AnyView(
                    ClipboardRowView(
                        row: row,
                        isSelected: row.id == selectedID,
                        isListActive: selectionActive,
                        listTopPadding: topPadding,
                        listBottomPadding: bottomPadding,
                        onSelect: { parent.onSelect($0) },
                        // 激活目标由行宿主按连击序列起点给 id，不是当前行。
                        onActivate: { parent.onActivate($0) },
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

        /// 原位替换一行内容，不动行视图与宿主，按住的手势不受影响。
        private func refreshRowContent(at index: Int, in tableView: NSTableView) {
            guard rows.indices.contains(index),
                  let makeRow,
                  let cell = tableView.view(atColumn: 0, row: index, makeIfNecessary: false)
                    as? ListRowCellView else { return }
            cell.setContent(makeRow(rows[index], topPadding(row: index), bottomPadding(row: index)))
        }

        /// 修正 NSTableView 自算高度偏高导致的多余底部空白；内容比视口短时仍撑满视口。
        func pinDocumentHeight(_ tableView: NSTableView, in scrollView: NSScrollView) {
            guard tableView.numberOfRows > 0 else { return }
            let content = tableView.rect(ofRow: tableView.numberOfRows - 1).maxY
            let target = max(content, scrollView.contentView.bounds.height)
            guard abs(tableView.frame.height - target) > ClipboardLayout.geometryTolerance else { return }
            tableView.frame.size.height = target
        }

        // MARK: - 数据源 / 代理

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            ClipboardLayout.rowHeight + topPadding(row: row) + bottomPadding(row: row)
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            if let recycled = tableView.makeView(withIdentifier: Self.rowViewIdentifier, owner: self)
                as? ListPlainRowView {
                return recycled
            }
            let rowView = ListPlainRowView()
            rowView.identifier = Self.rowViewIdentifier
            return rowView
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            let cell = (tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self)
                as? ListRowCellView)
                ?? ListRowCellView(identifier: Self.cellIdentifier)
            cell.setContent(
                makeRow?(
                    rows[row],
                    topPadding(row: row),
                    bottomPadding(row: row)
                ) ?? AnyView(Color.clear)
            )
            return cell
        }

        private func topPadding(row: Int) -> CGFloat {
            row == 0 ? ClipboardLayout.verticalPadding : 0
        }

        private func bottomPadding(row: Int) -> CGFloat {
            row == rows.count - 1 ? ClipboardLayout.verticalPadding : 0
        }

        /// 点击不改表格选中，选中真相只在 `NavigationState`。
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            false
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

        // MARK: - 观察

        func observe(_ scrollView: NSScrollView) {
            removeObservers()
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.publishTopVisibleRow()
                }
            }
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                MainActor.assumeIsolated {
                    guard let self, let scrollView else { return }
                    self.publishScrollerLayout(for: scrollView)
                    if let tableView = self.tableView {
                        self.pinDocumentHeight(tableView, in: scrollView)
                    }
                    self.syncColumnWidth(for: scrollView)
                }
            }
            styleObserver = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                MainActor.assumeIsolated {
                    guard let self, let scrollView else { return }
                    self.publishScrollerLayout(for: scrollView)
                }
            }
            // 行视图可能在按下与抬起之间被回收，用窗口级监听收口手势。
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) {
                [weak self] event in
                MainActor.assumeIsolated {
                    self?.handleClickMonitor(event)
                }
                return event
            }
        }

        /// 窗口级左键兜底；正常路径收口后追踪器已清空，不会重复落点。
        private func handleClickMonitor(_ event: NSEvent) {
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

        func removeObservers() {
            for token in [boundsObserver, frameObserver, styleObserver] {
                if let token { NotificationCenter.default.removeObserver(token) }
            }
            boundsObserver = nil
            frameObserver = nil
            styleObserver = nil
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
            }
            clickMonitor = nil
        }

        isolated deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            if let styleObserver {
                NotificationCenter.default.removeObserver(styleObserver)
            }
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
            }
        }

        // MARK: - 发布

        func needsScrollerLayoutPublish(for scrollView: NSScrollView) -> Bool {
            lastPublishedUsesOverlayScrollers != ScrollerLayoutProbe.usesOverlayScrollers(in: scrollView)
        }

        func publishScrollerLayout(for scrollView: NSScrollView) {
            let usesOverlay = ScrollerLayoutProbe.usesOverlayScrollers(in: scrollView)
            guard lastPublishedUsesOverlayScrollers != usesOverlay else { return }
            lastPublishedUsesOverlayScrollers = usesOverlay
            onScrollerLayoutChanged?(usesOverlay)
        }

        func publishTopVisibleRow() {
            guard let publish = onTopVisibleRowChanged, let tableView else { return }
            guard let range = fullyVisibleRowRange(in: tableView) else { return }
            guard range.lowerBound != lastPublishedTopVisibleRow else { return }
            lastPublishedTopVisibleRow = range.lowerBound
            if isInViewUpdate {
                DispatchQueue.main.async { publish(range.lowerBound) }
            } else {
                publish(range.lowerBound)
            }
        }

        /// 完整可见 = 整行落在可视矩形内；只喂「列表停在哪」这类策略。
        func fullyVisibleRowRange(in tableView: NSTableView) -> ClosedRange<Int>? {
            let visible = tableView.visibleRect
            let intersecting = tableView.rows(in: visible)
            guard intersecting.location != NSNotFound, intersecting.length > 0 else { return nil }
            let slack = visible.insetBy(dx: 0, dy: -ClipboardLayout.geometryTolerance)
            var first = intersecting.location
            var last = intersecting.location + intersecting.length - 1
            while first <= last, !slack.contains(tableView.rect(ofRow: first)) { first += 1 }
            while last >= first, !slack.contains(tableView.rect(ofRow: last)) { last -= 1 }
            guard first <= last else { return nil }
            return first...last
        }

        func syncColumnWidth(for scrollView: NSScrollView) {
            guard let tableView, let column = tableView.tableColumns.first else { return }
            let width = scrollView.contentView.bounds.width
            guard width > 0, abs(column.width - width) > ClipboardLayout.geometryTolerance else { return }
            column.width = width
        }
    }
}
