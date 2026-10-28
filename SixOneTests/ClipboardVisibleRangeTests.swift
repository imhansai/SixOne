//
//  ClipboardVisibleRangeTests.swift
//  SixOneTests
//  可见范围只算完整可见行；整表重建的发布让出一轮，普通滚动同步发布。

import AppKit
import Testing
@testable import SixOne

/// 按用例 id 记录完整可见范围，避免并行用例互相清计数。
private enum VisibleRangeProbe {
    nonisolated(unsafe) static var published: [UUID: [ClosedRange<Int>]] = [:]

    nonisolated static func record(_ id: UUID, range: ClosedRange<Int>) {
        published[id, default: []].append(range)
    }

    nonisolated static func count(_ id: UUID) -> Int {
        published[id]?.count ?? 0
    }
}

@Suite("列表可见行发布")
@MainActor
struct ClipboardVisibleRangeTests {
    private static let rowCount = 40

    private func makeCoordinator(id: UUID) -> HistoryListTableView.Coordinator {
        HistoryListTableView.Coordinator(
            onVisibleRowRangeChanged: { range in
                VisibleRangeProbe.record(id, range: range)
            },
            onScrollerLayoutChanged: nil
        )
    }

    /// 离屏窗口挂真实表格；`rows(in:)` 需要窗口与布局。
    private func makeHostedTable(
        _ coordinator: HistoryListTableView.Coordinator,
        rows: [HistoryRow]
    ) throws -> (scrollView: NSScrollView, tableView: NSTableView, window: NSWindow) {
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: ClipboardLayout.panelWidth, height: 491)
        )
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.automaticallyAdjustsContentInsets = false

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        tableView.rowHeight = ClipboardLayout.rowHeight
        tableView.usesAutomaticRowHeights = false
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row")))
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        scrollView.documentView = tableView

        coordinator.tableView = tableView
        let parent = try makeParent(rows: rows)
        coordinator.apply(parent)
        coordinator.syncRows(with: parent, in: tableView)

        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: ClipboardLayout.panelWidth, height: 491),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.orderFrontRegardless()
        scrollView.layoutSubtreeIfNeeded()
        tableView.layoutSubtreeIfNeeded()
        return (scrollView, tableView, window)
    }

    private func makeParent(rows: [HistoryRow]) throws -> HistoryListTableView {
        HistoryListTableView(
            context: try TestPanel.context(),
            rows: rows,
            dataRevision: 0,
            locale: Locale(identifier: "en"),
            selectedItemID: nil,
            scrollRevision: 0,
            onSelect: { _ in },
            onActivate: { _, _ in },
            onCopy: { _ in },
            menuProvider: { _, _ in nil }
        )
    }

    private func makeRows() -> [HistoryRow] {
        (0..<Self.rowCount).map { HistoryRow.stub(title: "第 \($0) 行") }
    }

    @Test("更新周期内的发布排到下一轮")
    func defersPublishInsideViewUpdate() async throws {
        let id = UUID()
        let coordinator = makeCoordinator(id: id)
        let (_, _, window) = try makeHostedTable(coordinator, rows: makeRows())
        defer { window.orderOut(nil) }

        coordinator.isInViewUpdate = true
        coordinator.publishVisibleRowRange()
        #expect(VisibleRangeProbe.count(id) == 0, "更新周期内不该同步写回")

        coordinator.isInViewUpdate = false
        let published = await Wait.until { VisibleRangeProbe.count(id) == 1 }
        #expect(published)
    }

    @Test("普通滚动的发布仍是同步的")
    func publishesSynchronouslyOutsideViewUpdate() throws {
        let id = UUID()
        let coordinator = makeCoordinator(id: id)
        let (_, _, window) = try makeHostedTable(coordinator, rows: makeRows())
        defer { window.orderOut(nil) }

        coordinator.publishVisibleRowRange()
        #expect(VisibleRangeProbe.count(id) == 1)
    }

    @Test("首屏从第 0 行开始，范围与表格判定一致")
    func publishesRangeFromTableView() throws {
        let id = UUID()
        let coordinator = makeCoordinator(id: id)
        let (_, tableView, window) = try makeHostedTable(coordinator, rows: makeRows())
        defer { window.orderOut(nil) }

        coordinator.publishVisibleRowRange()
        let published = try #require(VisibleRangeProbe.published[id]?.first)
        let expected = try #require(coordinator.fullyVisibleRowRange(in: tableView))
        #expect(published == expected)
        #expect(published.lowerBound == 0)
    }

    @Test("只露一角的行不算可见：滚到半行处，范围首末都是完整行")
    func excludesPartiallyVisibleRows() throws {
        let id = UUID()
        let coordinator = makeCoordinator(id: id)
        let (scrollView, tableView, window) = try makeHostedTable(coordinator, rows: makeRows())
        defer { window.orderOut(nil) }

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: ClipboardLayout.rowHeight * 3 - 20))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        coordinator.publishVisibleRowRange()
        let range = try #require(VisibleRangeProbe.published[id]?.last)
        let visible = tableView.visibleRect
        #expect(range.lowerBound > 0, "上边缘的半行被算成可见")
        #expect(visible.contains(tableView.rect(ofRow: range.lowerBound)), "首行不完整还算可见")
        #expect(visible.contains(tableView.rect(ofRow: range.upperBound)), "末行不完整还算可见")
        #expect(
            !visible.contains(tableView.rect(ofRow: range.lowerBound - 1)),
            "上边缘的半行被算成可见"
        )
        if range.upperBound < Self.rowCount - 1 {
            #expect(
                !visible.contains(tableView.rect(ofRow: range.upperBound + 1)),
                "下边缘的半行被算成可见"
            )
        }
    }
}
