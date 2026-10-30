//
//  GroupListTableView.swift
//  SixOne
//
//  文件组列表容器：沿用历史列表的虚拟化与点击收口；选中真相在 PreviewState，
//  行按原始下标定位。
//

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
    /// 按住 ⌘ 时的编号范围。
    var quickPasteRange: ClosedRange<Int>? = nil
    var onVisibleRowRangeChanged: ((ClosedRange<Int>) -> Void)? = nil
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
        let (scrollView, tableView) = ListTableScaffold.make(
            columnIdentifier: Coordinator.columnIdentifier
        )
        scrollView.isScrollBlocked = isScrollBlocked
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        context.coordinator.tableView = tableView
        context.coordinator.apply(self)
        context.coordinator.observe(scrollView)
        // 首轮布局需让出一轮。
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
        // 更新中触发的发布排到下一轮，避免写回 body 正在读的状态。
        context.coordinator.isInViewUpdate = true
        defer { context.coordinator.isInViewUpdate = false }
        context.coordinator.apply(self)

        if context.coordinator.syncRows(with: self, in: tableView) {
            context.coordinator.pinDocumentHeight(tableView, in: scrollView)
            // 行数变短不产生边界通知，补一轮重算。
            DispatchQueue.main.async {
                context.coordinator.publishVisibleRowRange()
            }
        }

        // 选中外观、编号、选中镜像与滚动在同一无动画事务里完成。
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = 0
            animation.allowsImplicitAnimation = false
            context.coordinator.syncSelectionAppearance(in: tableView)
            context.coordinator.syncQuickPasteHints(in: tableView)
            context.coordinator.syncSelection(in: tableView)
            context.coordinator.performPendingScroll()
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.removeObservers()
    }

    // MARK: - 协调器

    final class Coordinator: ListTableCoordinator {
        static let columnIdentifier = NSUserInterfaceItemIdentifier("SixOneGroupFileRow")
        static let cellIdentifier = NSUserInterfaceItemIdentifier("SixOneGroupFileRowCell")
        static let rowViewIdentifier = NSUserInterfaceItemIdentifier("SixOneGroupFileRowView")

        private var files: [GroupFileEntry] = []
        private var makeRow: ((GroupFileEntry, Int, CGFloat, CGFloat) -> AnyView)?
        private var selectedIndex: Int?
        private var isListActive = false
        private var quickPasteRange: ClosedRange<Int>?
        private var rowIndexByID: [UUID: Int] = [:]
        private let rowStates = GroupRowStateStore()
        private var onSelect: ((Int?) -> Void)?
        private var onCommand: ((GroupFileCommand, Int) -> Void)?

        /// 语言变化需重建行内文案。
        private var reloadedLocale: Locale?
        private var mirroredSelectionIndex: Int?
        private struct RenderedSelection: Equatable {
            var index: Int?
            var isActive: Bool
        }
        private var renderedSelection = RenderedSelection(index: nil, isActive: false)
        private var renderedQuickPasteRange: ClosedRange<Int>?

        private var scrollRequest: GroupScrollRequest?
        private var scrollRequestID = 0
        private var handledScrollRequestID: Int?
        private var blankPressLocation: NSPoint?

        init() {
            super.init(onVisibleRowRangeChanged: nil, onScrollerLayoutChanged: nil)
            // 空结果时表格仍撑满视口，空态说明浮在上面。
            pinsEmptyDocumentHeight = true
        }

        // MARK: - 行数据

        override var rowCount: Int { files.count }
        override var rowViewIdentifier: NSUserInterfaceItemIdentifier { Self.rowViewIdentifier }
        override var cellIdentifier: NSUserInterfaceItemIdentifier { Self.cellIdentifier }

        override func topPadding(row: Int) -> CGFloat {
            row == 0 ? ClipboardLayout.groupListPadding : 0
        }

        override func bottomPadding(row: Int) -> CGFloat {
            row == files.count - 1 ? ClipboardLayout.groupListPadding : 0
        }

        override func makeRowContent(at index: Int, topPadding: CGFloat, bottomPadding: CGFloat) -> AnyView {
            guard files.indices.contains(index), let makeRow else { return AnyView(Color.clear) }
            return makeRow(files[index], index, topPadding, bottomPadding)
        }

        func apply(_ parent: GroupListTableView) {
            selectedIndex = parent.selectedIndex
            isListActive = parent.isListActive
            quickPasteRange = parent.quickPasteRange
            scrollRequest = parent.scrollRequest
            scrollRequestID = parent.scrollRequestID
            onSelect = parent.onSelect
            onCommand = parent.onCommand
            onVisibleRowRangeChanged = parent.onVisibleRowRangeChanged

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
            let quickPasteRange = parent.quickPasteRange
            let rowStates = rowStates
            makeRow = { [
                context = parent.context,
                locale = parent.locale,
                displayScale = parent.displayScale
            ] file, rowIndex, topPadding, bottomPadding in
                AnyView(
                    FileGroupRow(
                        file: file,
                        state: rowStates.state(for: file.index),
                        rowID: file.rowID,
                        clickTracker: tracker,
                        shortcutNumber: QuickPaste.shortcutNumber(forRow: rowIndex, in: quickPasteRange),
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
            // 重建后范围相同也要重发，外部状态可能已清空。
            invalidatePublishedVisibleRowRange()
            tableView.reloadData()
            renderedSelection = RenderedSelection(index: selectedIndex, isActive: isListActive)
            return true
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

        /// 编号变化时只刷新涉及的行。
        func syncQuickPasteHints(in tableView: NSTableView) {
            guard quickPasteRange != renderedQuickPasteRange else { return }
            let previous = renderedQuickPasteRange
            renderedQuickPasteRange = quickPasteRange
            var indices: Set<Int> = []
            for range in [previous, quickPasteRange].compactMap({ $0 }) {
                indices.formUnion(range)
            }
            for index in indices.sorted() where files.indices.contains(index) {
                refreshRowContent(at: index, in: tableView)
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
            guard let scrollView = listScrollView, let tableView else { return }
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

        /// 布局落定后补一次挂起的滚动请求。
        override func scrollViewDidLayout() {
            performPendingScroll()
        }

        // MARK: - 点击

        /// 窗口级左键兜底：行在按下/抬起间被回收时仍能完成落点。
        override func handleClickMonitor(_ event: NSEvent) {
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
