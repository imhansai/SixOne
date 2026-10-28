//
//  GroupListTableView.swift
//  SixOne
//
//  文件组列表容器：沿用 HistoryListTableView 的虚拟化；选中真相在 PreviewState，行按原始下标定位。

import AppKit
import SwiftUI

struct GroupListTableView: NSViewRepresentable {
    let context: PanelContext
    let files: [GroupFileEntry]
    let selectedIndex: Int?
    let isListActive: Bool
    let sourceAppBundleIdentifier: String?
    let thumbnailCache: FileGroupThumbnailCache
    let scrollRequest: GroupScrollRequest?
    let scrollRequestID: Int
    /// 确认弹窗期间停掉用户滚动（程序化滚动不受影响）。
    var isScrollBlocked = false
    let locale: Locale
    let displayScale: CGFloat

    let onSelect: (Int?) -> Void
    let onPreview: (Int) -> Void
    let onCommand: (GroupFileCommand, Int) -> Void
    let onShare: (Int, NSView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ListScrollView()
        scrollView.isScrollBlocked = isScrollBlocked
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.hasVerticalScroller = true
        // 不设 contentInsets：它会把可滚动范围撑到内容之外。
        scrollView.automaticallyAdjustsContentInsets = false

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        // 表格不画选中，高亮由行视图自绘。
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.intercellSpacing = .zero
        // 行高由 heightOfRow 给，首末行含列表留白。
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
        // 重新 tiling 后列宽与文档高度需要重新对齐。
        scrollView.contentView.postsFrameChangedNotifications = true
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        context.coordinator.apply(self)
        context.coordinator.observe(scrollView)
        // 首轮布局需让出一轮。
        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView else { return }
            context.coordinator.pinDocumentHeight(tableView, in: scrollView)
            context.coordinator.syncColumnWidth(for: scrollView)
            context.coordinator.performPendingScroll()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView,
              let listScrollView = scrollView as? ListScrollView else { return }
        listScrollView.isScrollBlocked = isScrollBlocked
        context.coordinator.apply(self)

        if context.coordinator.syncRows(with: self, in: tableView) {
            context.coordinator.pinDocumentHeight(tableView, in: scrollView)
        }

        // 选中外观、选中镜像与滚动在同一无动画事务里完成。
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = 0
            animation.allowsImplicitAnimation = false
            context.coordinator.syncSelectionAppearance(in: tableView)
            context.coordinator.syncSelection(in: tableView)
            context.coordinator.performPendingScroll()
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.removeObservers()
    }

    // MARK: - 协调器

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let columnIdentifier = NSUserInterfaceItemIdentifier("SixOneGroupFileRow")
        static let cellIdentifier = NSUserInterfaceItemIdentifier("SixOneGroupFileRowCell")
        static let rowViewIdentifier = NSUserInterfaceItemIdentifier("SixOneGroupFileRowView")

        private var files: [GroupFileEntry] = []
        private var makeRow: ((GroupFileEntry, CGFloat, CGFloat) -> AnyView)?
        private var selectedIndex: Int?
        private var isListActive = false
        /// 所有行宿主共用，重建列表不丢点击。
        let rowClickTracker = RowClickTracker()
        private var rowIndexByID: [UUID: Int] = [:]
        private let rowStates = GroupRowStateStore()
        var onSelect: ((Int?) -> Void)?
        private var onCommand: ((GroupFileCommand, Int) -> Void)?

        /// 语言变化需重建行内文案。
        private var reloadedLocale: Locale?
        private var mirroredSelectionIndex: Int?
        private struct RenderedSelection: Equatable {
            var index: Int?
            var isActive: Bool
        }
        private var renderedSelection = RenderedSelection(index: nil, isActive: false)

        private var scrollRequest: GroupScrollRequest?
        private var scrollRequestID = 0
        private var handledScrollRequestID: Int?

        weak var tableView: NSTableView?
        weak var scrollView: ListScrollView?
        private var frameObserver: NSObjectProtocol?
        private var clickMonitor: Any?
        private var blankPressLocation: NSPoint?

        isolated deinit {
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
            }
        }

        // MARK: - 装载

        func apply(_ parent: GroupListTableView) {
            selectedIndex = parent.selectedIndex
            isListActive = parent.isListActive
            scrollRequest = parent.scrollRequest
            scrollRequestID = parent.scrollRequestID
            onSelect = parent.onSelect
            onCommand = parent.onCommand

            let tracker = rowClickTracker
            // 点击落点由列表收口：抬起可能落在别的行上，闭包不能跟着行走。
            rowClickTracker.onSelect = { [weak self] rowID in
                guard let self, let index = self.rowIndexByID[rowID] else { return }
                self.onSelect?(index)
            }
            rowClickTracker.onActivate = { [weak self] rowID, _ in
                guard let self, let index = self.rowIndexByID[rowID] else { return }
                self.onCommand?(.paste, index)
            }

            let selected = parent.selectedIndex
            let active = parent.isListActive
            let rowStates = rowStates
            makeRow = { [context = parent.context, locale = parent.locale, displayScale = parent.displayScale] file, topPadding, bottomPadding in
                AnyView(
                    FileGroupRow(
                        file: file,
                        state: rowStates.state(for: file.index),
                        rowID: file.rowID,
                        clickTracker: tracker,
                        isSelected: file.index == selected,
                        isListActive: active,
                        sourceAppBundleIdentifier: parent.sourceAppBundleIdentifier,
                        thumbnailCache: parent.thumbnailCache,
                        displayScale: displayScale,
                        listTopPadding: topPadding,
                        listBottomPadding: bottomPadding,
                        onSelect: parent.onSelect,
                        onPreview: parent.onPreview,
                        onCommand: parent.onCommand,
                        onShare: parent.onShare
                    )
                    // 内容变化时换身份，避免行内视图状态残留。
                    .id(file)
                    .environment(context)
                    .environment(\.locale, locale)
                )
            }
        }

        func syncRows(with parent: GroupListTableView, in tableView: NSTableView) -> Bool {
            let localeChanged = reloadedLocale != parent.locale
            guard localeChanged || files != parent.files else { return false }

            let newFiles = parent.files
            reloadedLocale = parent.locale
            if files != newFiles {
                rowIndexByID.removeAll(keepingCapacity: true)
                for file in newFiles {
                    rowIndexByID[file.rowID] = file.index
                }
            }
            let idsChanged = files.count != newFiles.count
                || zip(files, newFiles).contains { pair in pair.0.rowID != pair.1.rowID }
            guard localeChanged || idsChanged else {
                let oldFiles = files
                files = newFiles
                for (index, pair) in zip(oldFiles, newFiles).enumerated() where pair.0 != pair.1 {
                    refreshRowContent(at: index, in: tableView)
                }
                return false
            }

            files = newFiles
            // 重建会清掉表格选中，下一轮重新同步。
            mirroredSelectionIndex = nil
            tableView.reloadData()
            renderedSelection = RenderedSelection(index: selectedIndex, isActive: isListActive)
            return true
        }

        /// 原位替换行内容，不动行视图与按住中的手势。
        private func refreshRowContent(at index: Int, in tableView: NSTableView) {
            guard files.indices.contains(index),
                  let makeRow,
                  let cell = tableView.view(atColumn: 0, row: index, makeIfNecessary: false)
                    as? ListRowCellView else { return }
            cell.setContent(makeRow(files[index], topPadding(row: index), bottomPadding(row: index)))
        }

        func pinDocumentHeight(_ tableView: NSTableView, in scrollView: NSScrollView) {
            let content = tableView.numberOfRows > 0
                ? tableView.rect(ofRow: tableView.numberOfRows - 1).maxY
                : 0
            let target = max(content, scrollView.contentView.bounds.height)
            guard abs(tableView.frame.height - target) > ClipboardLayout.geometryTolerance else { return }
            tableView.frame.size.height = target
        }

        // MARK: - 数据源 / 代理

        func numberOfRows(in tableView: NSTableView) -> Int {
            files.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            ClipboardLayout.rowHeight + topPadding(row: row) + bottomPadding(row: row)
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            // ListPlainRowView 无状态，按 identifier 回收复用安全。
            if let recycled = tableView.makeView(withIdentifier: Self.rowViewIdentifier, owner: self)
                as? ListPlainRowView {
                return recycled
            }
            let rowView = ListPlainRowView()
            rowView.identifier = Self.rowViewIdentifier
            return rowView
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard files.indices.contains(row) else { return nil }
            let cell = (tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self)
                as? ListRowCellView)
                ?? ListRowCellView(identifier: Self.cellIdentifier)
            cell.setContent(
                makeRow?(
                    files[row],
                    topPadding(row: row),
                    bottomPadding(row: row)
                ) ?? AnyView(Color.clear)
            )
            return cell
        }

        private func topPadding(row: Int) -> CGFloat {
            row == 0 ? ClipboardLayout.groupListPadding : 0
        }

        private func bottomPadding(row: Int) -> CGFloat {
            row == files.count - 1 ? ClipboardLayout.groupListPadding : 0
        }

        /// 点击不改表格选中，真相只在 PreviewState。
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            false
        }

        // MARK: - 选中外观

        func syncSelectionAppearance(in tableView: NSTableView) {
            let current = RenderedSelection(index: selectedIndex, isActive: isListActive)
            guard current != renderedSelection else { return }
            let previous = renderedSelection
            renderedSelection = current
            for index in Set([previous.index, current.index].compactMap { $0 }) {
                guard let position = files.firstIndex(where: { $0.index == index }) else { continue }
                refreshRowContent(at: position, in: tableView)
            }
        }

        // MARK: - 选中镜像

        /// 模型 → 表格的单向选中镜像。
        func syncSelection(in tableView: NSTableView) {
            guard let selectedIndex else {
                guard mirroredSelectionIndex != nil else { return }
                mirroredSelectionIndex = nil
                tableView.deselectAll(nil)
                return
            }
            guard mirroredSelectionIndex != selectedIndex,
                  let position = files.firstIndex(where: { $0.index == selectedIndex }) else { return }
            mirroredSelectionIndex = selectedIndex
            tableView.selectRowIndexes(IndexSet(integer: position), byExtendingSelection: false)
        }

        // MARK: - 滚动

        /// 执行未落定的滚动请求；视口未布局时等下次 frame。
        func performPendingScroll() {
            guard handledScrollRequestID != scrollRequestID else { return }
            guard let request = scrollRequest else {
                handledScrollRequestID = scrollRequestID
                return
            }
            guard !files.isEmpty else {
                handledScrollRequestID = scrollRequestID
                return
            }
            guard let scrollView, let tableView else { return }
            let visible = scrollView.contentView.bounds
            guard visible.height > 0 else { return }

            let position: Int
            switch request {
            case .top:
                position = 0
            case .row(let fileIndex):
                guard let found = files.firstIndex(where: { $0.index == fileIndex }) else {
                    handledScrollRequestID = scrollRequestID
                    return
                }
                position = found
            }

            handledScrollRequestID = scrollRequestID
            let targetY = FileGroupListScrollGeometry.targetOriginY(
                rowRect: tableView.rect(ofRow: position),
                visible: visible,
                documentHeight: tableView.frame.height
            )
            // 视口无位移就不点亮滚动条，避免选中变化引发闪烁。
            guard abs(targetY - visible.minY) >= ClipboardLayout.geometryTolerance else { return }
            scrollView.scrollViewport(toY: targetY)
        }

        // MARK: - 观察

        func observe(_ scrollView: NSScrollView) {
            removeObservers()
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                MainActor.assumeIsolated {
                    guard let self, let scrollView, let tableView = self.tableView else { return }
                    self.pinDocumentHeight(tableView, in: scrollView)
                    self.syncColumnWidth(for: scrollView)
                    // 首次布局才拿得到视口高度，挂起的滚动在这里补一次。
                    self.performPendingScroll()
                }
            }
            // 行视图可能在按下与抬起间被回收，由事件监听兜底。
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) {
                [weak self] event in
                MainActor.assumeIsolated {
                    self?.handleClickMonitor(event)
                }
                return event
            }
        }

        /// 窗口级左键兜底：行在按下/抬起间被回收时仍能完成落点。
        private func handleClickMonitor(_ event: NSEvent) {
            guard let tableView, event.window === tableView.window else { return }
            switch event.type {
            case .leftMouseDown:
                // 新按下取代未收口的旧手势（如上次抬起在窗口外）。
                rowClickTracker.cancel()
                blankPressLocation = isBlankArea(event, in: tableView) ? event.locationInWindow : nil
            case .leftMouseUp:
                if let press = blankPressLocation {
                    blankPressLocation = nil
                    completeBlankClick(event, in: tableView, pressLocation: press)
                    return
                }
                guard let pressed = rowClickTracker.pressedRowID else { return }
                guard let position = files.firstIndex(where: { $0.rowID == pressed }) else {
                    rowClickTracker.cancel()
                    return
                }
                // 是否拖出按按下条目当前矩形判定，滚走/重排不算拖出。
                let point = tableView.convert(event.locationInWindow, from: nil)
                rowClickTracker.end(
                    event: event,
                    releaseInsideRow: tableView.rect(ofRow: position).contains(point)
                )
            default:
                break
            }
        }

        private func isBlankArea(_ event: NSEvent, in tableView: NSTableView) -> Bool {
            guard RowHitPolicy.isPlainLeftClick(event.type, modifiers: event.modifierFlags) else {
                return false
            }
            let point = tableView.convert(event.locationInWindow, from: nil)
            guard tableView.bounds.contains(point), tableView.row(at: point) == -1 else { return false }
            // 滚动条等子视图也可能落在此处，只认真正命中的表体。
            return tableView.window?.contentView?.hitTest(event.locationInWindow) === tableView
        }

        private func completeBlankClick(
            _ event: NSEvent,
            in tableView: NSTableView,
            pressLocation: NSPoint
        ) {
            guard isBlankArea(event, in: tableView) else { return }
            let travel = hypot(
                event.locationInWindow.x - pressLocation.x,
                event.locationInWindow.y - pressLocation.y
            )
            guard travel <= RowHitPolicy.clickPointerSlop else { return }
            onSelect?(nil)
        }

        func removeObservers() {
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            frameObserver = nil
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
            }
            clickMonitor = nil
        }

        /// 列宽跟随可视宽度；常规重排由 autoresizing 完成。
        func syncColumnWidth(for scrollView: NSScrollView) {
            guard let tableView, let column = tableView.tableColumns.first else { return }
            let width = scrollView.contentView.bounds.width
            guard width > 0, abs(column.width - width) > ClipboardLayout.geometryTolerance else { return }
            column.width = width
        }
    }
}

@MainActor
final class GroupRowStateStore {
    private var states: [Int: FileGroupRowState] = [:]

    func state(for index: Int) -> FileGroupRowState {
        if let state = states[index] { return state }
        let state = FileGroupRowState()
        states[index] = state
        return state
    }
}
