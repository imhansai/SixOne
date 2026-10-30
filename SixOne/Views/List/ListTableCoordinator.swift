//
//  ListTableCoordinator.swift
//  SixOne
//
//  历史列表与文件组列表共用的 NSTableView 协调器：行复用、高度、文档高度、
//  可见范围发布与滚动/点击观察。子类只提供行数据、行内容与差异刷新。
//

import AppKit
import SwiftUI

class ListTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    weak var tableView: NSTableView?
    weak var listScrollView: ListScrollView?
    var isInViewUpdate = false
    var onVisibleRowRangeChanged: ((ClosedRange<Int>) -> Void)?
    var onScrollerLayoutChanged: ((Bool) -> Void)?
    /// 历史列表跟随滚动条形态；文件组列表不关心。
    var observesScrollerStyle = false
    /// 空列表是否也要撑满视口（文件组空态浮在表格上）。
    var pinsEmptyDocumentHeight = false
    let rowClickTracker = RowClickTracker()

    private var lastPublishedVisibleRowRange: ClosedRange<Int>?
    private var lastPublishedUsesOverlayScrollers: Bool?
    private var boundsObserver: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?
    private var styleObserver: NSObjectProtocol?
    private var clickMonitor: Any?

    init(
        onVisibleRowRangeChanged: ((ClosedRange<Int>) -> Void)?,
        onScrollerLayoutChanged: ((Bool) -> Void)?
    ) {
        self.onVisibleRowRangeChanged = onVisibleRowRangeChanged
        self.onScrollerLayoutChanged = onScrollerLayoutChanged
    }

    // MARK: - 子类提供

    var rowCount: Int { 0 }
    var rowViewIdentifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier("SixOne.ListRowView") }
    var cellIdentifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier("SixOne.ListRowCell") }

    func makeRowContent(at index: Int, topPadding: CGFloat, bottomPadding: CGFloat) -> AnyView {
        AnyView(Color.clear)
    }

    func topPadding(row: Int) -> CGFloat { 0 }
    func bottomPadding(row: Int) -> CGFloat { 0 }
    func handleClickMonitor(_ event: NSEvent) {}
    func scrollViewDidLayout() {}

    // MARK: - 数据源 / 代理

    func numberOfRows(in tableView: NSTableView) -> Int {
        rowCount
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        ClipboardLayout.rowHeight + topPadding(row: row) + bottomPadding(row: row)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        if let recycled = tableView.makeView(withIdentifier: rowViewIdentifier, owner: self)
            as? ListPlainRowView {
            return recycled
        }
        let rowView = ListPlainRowView()
        rowView.identifier = rowViewIdentifier
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < rowCount else { return nil }
        let cell = (tableView.makeView(withIdentifier: cellIdentifier, owner: self)
            as? ListRowCellView)
            ?? ListRowCellView(identifier: cellIdentifier)
        cell.setContent(makeRowContent(
            at: row,
            topPadding: topPadding(row: row),
            bottomPadding: bottomPadding(row: row)
        ))
        return cell
    }

    /// 点击不改表格选中，选中真相在各列表自己的状态里。
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }

    /// 原位替换一行内容，不动行视图与宿主，按住的手势不受影响。
    func refreshRowContent(at index: Int, in tableView: NSTableView) {
        guard index >= 0, index < rowCount,
              let cell = tableView.view(atColumn: 0, row: index, makeIfNecessary: false)
                as? ListRowCellView else { return }
        cell.setContent(makeRowContent(
            at: index,
            topPadding: topPadding(row: index),
            bottomPadding: bottomPadding(row: index)
        ))
    }

    /// 修正 NSTableView 自算高度偏高导致的多余底部空白；内容比视口短时仍撑满视口。
    func pinDocumentHeight(_ tableView: NSTableView, in scrollView: NSScrollView) {
        guard tableView.numberOfRows > 0 || pinsEmptyDocumentHeight else { return }
        let content = tableView.numberOfRows > 0
            ? tableView.rect(ofRow: tableView.numberOfRows - 1).maxY
            : 0
        let target = max(content, scrollView.contentView.bounds.height)
        guard abs(tableView.frame.height - target) > ClipboardLayout.geometryTolerance else { return }
        tableView.frame.size.height = target
    }

    /// 列宽跟随可视宽度；常规重排由 autoresizing 完成。
    func syncColumnWidth(for scrollView: NSScrollView) {
        guard let tableView, let column = tableView.tableColumns.first else { return }
        let width = scrollView.contentView.bounds.width
        guard width > 0, abs(column.width - width) > ClipboardLayout.geometryTolerance else { return }
        column.width = width
    }

    // MARK: - 可见范围与滚动条

    func publishVisibleRowRange() {
        guard let publish = onVisibleRowRangeChanged, let tableView else { return }
        guard let range = ListRowVisibility.fullyVisibleRowRange(in: tableView) else { return }
        guard range != lastPublishedVisibleRowRange else { return }
        lastPublishedVisibleRowRange = range
        if isInViewUpdate {
            DispatchQueue.main.async { publish(range) }
        } else {
            publish(range)
        }
    }

    /// 整表重建后强制重发一次可见范围，外部状态可能已经清空。
    func invalidatePublishedVisibleRowRange() {
        lastPublishedVisibleRowRange = nil
    }

    func needsScrollerLayoutPublish(for scrollView: NSScrollView) -> Bool {
        lastPublishedUsesOverlayScrollers != ScrollerLayoutProbe.usesOverlayScrollers(in: scrollView)
    }

    func publishScrollerLayout(for scrollView: NSScrollView) {
        let usesOverlay = ScrollerLayoutProbe.usesOverlayScrollers(in: scrollView)
        guard lastPublishedUsesOverlayScrollers != usesOverlay else { return }
        lastPublishedUsesOverlayScrollers = usesOverlay
        onScrollerLayoutChanged?(usesOverlay)
    }

    // MARK: - 观察

    /// 首轮布局后补齐文档高度、列宽与可见范围。
    func performInitialLayout(in scrollView: NSScrollView) {
        guard let tableView else { return }
        if observesScrollerStyle {
            publishScrollerLayout(for: scrollView)
        }
        pinDocumentHeight(tableView, in: scrollView)
        syncColumnWidth(for: scrollView)
        scrollViewDidLayout()
        publishVisibleRowRange()
    }

    func observe(_ scrollView: NSScrollView) {
        removeObservers()
        listScrollView = scrollView as? ListScrollView
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publishVisibleRowRange()
            }
        }
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            MainActor.assumeIsolated {
                guard let self, let scrollView, let tableView = self.tableView else { return }
                if self.observesScrollerStyle {
                    self.publishScrollerLayout(for: scrollView)
                }
                self.pinDocumentHeight(tableView, in: scrollView)
                self.syncColumnWidth(for: scrollView)
                self.scrollViewDidLayout()
                // 面板首次显示/布局变化时补发可见范围，不能只等滚动通知。
                self.publishVisibleRowRange()
            }
        }
        if observesScrollerStyle {
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
        for token in [boundsObserver, frameObserver, styleObserver] {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
    }
}

/// 两个列表共用的滚动视图 / 表格装配。
@MainActor
enum ListTableScaffold {
    static func make(
        columnIdentifier: NSUserInterfaceItemIdentifier,
        initialColumnWidth: CGFloat = ClipboardLayout.panelWidth
    ) -> (scrollView: ListScrollView, tableView: NSTableView) {
        let scrollView = ListScrollView()
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
        // 表格不画选中，高亮由行视图自绘。
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

        let column = NSTableColumn(identifier: columnIdentifier)
        column.resizingMask = .autoresizingMask
        column.width = initialColumnWidth
        column.minWidth = 120
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        // 重新 tiling 后列宽与文档高度需要重新对齐。
        scrollView.contentView.postsFrameChangedNotifications = true
        return (scrollView, tableView)
    }
}
