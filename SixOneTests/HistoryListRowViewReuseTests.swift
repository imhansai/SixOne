//
//  HistoryListRowViewReuseTests.swift
//  SixOneTests
//  行视图复用回归：扫全表统计不同行视图实例数，超过阈值即未复用。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("历史列表行视图复用")
@MainActor
struct HistoryListRowViewReuseTests {
    private static let viewportSize = NSSize(width: 640, height: 491)

    private func makeRows(_ count: Int) -> [HistoryRow] {
        (0..<count).map { HistoryRow.stub(title: "第 \($0) 行") }
    }

    private func makeView(
        _ context: PanelContext,
        rows: [HistoryRow],
        target: HistoryListScrollTarget?
    ) -> AnyView {
        if let target {
            switch target {
            case .row(let id):
                context.navigationState.requestScroll(toRow: id)
            case .top:
                context.navigationState.requestScrollToTop()
            }
        }
        return AnyView(
            HistoryListTableView(
                context: context,
                rows: rows,
                dataRevision: 0,
                locale: Locale(identifier: "zh-Hans"),
                selectedItemID: nil,
                scrollRevision: context.navigationState.scrollRevision,
                onSelect: { _ in },
                onActivate: { _, _ in },
                onCopy: { _ in },
                menuProvider: { _, _ in nil }
            )
        )
    }

    @Test("来回扫全表时行视图实例数保持有界")
    func rowViewsAreReusedAcrossFullSweeps() async throws {
        let context = try TestPanel.context()
        let rows = makeRows(300)

        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, target: nil),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host))
        let tableView = try #require(scrollView.documentView as? NSTableView)
        let ready = await Wait.until { tableView.numberOfRows == rows.count }
        #expect(ready, "行没有落进表格")

        var seenRowViews = Set<ObjectIdentifier>()
        func sampleVisibleRowViews() {
            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.location != NSNotFound, visible.length > 0 else { return }
            for row in visible.location..<(visible.location + visible.length) {
                if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) {
                    seenRowViews.insert(ObjectIdentifier(rowView))
                }
            }
        }

        var misses = 0
        let passes: [[Int]] = [Array(0..<rows.count), Array((0..<rows.count).reversed())]
        for pass in passes {
            for index in pass {
                host.rootView = makeView(context, rows: rows, target: .row(rows[index].id))
                let reached = await Wait.until(timeout: .seconds(2), interval: .milliseconds(5)) {
                    scrollView.documentVisibleRect.contains(tableView.rect(ofRow: index))
                }
                if !reached { misses += 1 }
                sampleVisibleRowViews()
            }
        }

        #expect(misses == 0, "用例没走到真实滚动路径（\(misses) 步没滚到目标）")
        #expect(
            seenRowViews.count <= 64,
            "行视图没有被复用：一趟来回共出现 \(seenRowViews.count) 个不同行视图实例"
        )
    }
}
