//
//  ClipboardListViewTests.swift
//  SixOneTests
//  整条列表视图在离屏窗口装配一次，兜底视图树与行宿主接线。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("列表视图装配")
@MainActor
struct ClipboardListViewTests {
    private static let rowCount = 40

    @Test("列表视图把行落进 NSTableView，行交互宿主就在单元格里")
    func listViewRendersRowsIntoTableView() async throws {
        let harness = try ClipboardHarness()
        let rows = (0..<Self.rowCount).map { HistoryRow.stub(title: "第 \($0) 行") }
        let store = HistoryListStore(
            repository: FakeHistoryRepository(rowsByQuery: ["": rows]),
            events: ClipboardHistoryEventBus()
        )
        await store.loadLatestAndWait()
        #expect(store.rows.count == Self.rowCount)

        let context = PanelContext(manager: harness.manager, store: store, caches: PanelCaches())
        let view = AnyView(
            ClipboardListView(context: context)
                .environment(context)
                .environment(\.locale, RuntimeLanguage.shared.locale)
                .environment(RuntimeLanguage.shared)
        )

        let (host, window) = OffscreenHost.make(view, size: ClipboardLayout.panelSize)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "列表没有建出滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView, "列表容器不是 NSTableView")
        let filled = await Wait.until { tableView.numberOfRows == Self.rowCount }
        #expect(filled, "表格行数与数据源对不上")
        #expect(tableView.rows(in: tableView.visibleRect).length > 0, "视口里一行都没有")

        let hostsMounted = await Wait.until {
            !OffscreenHost.allSubviews(of: host).compactMap { $0 as? RowInteractionHost.HostView }.isEmpty
        }
        #expect(hostsMounted, "行交互宿主没挂进单元格")

        let clipWidth = scrollView.contentView.bounds.width
        #expect(abs(tableView.frame.width - clipWidth) < 1, "表格没有铺满可视宽度")
        let firstCell = try #require(
            tableView.view(atColumn: 0, row: 0, makeIfNecessary: false),
            "第 0 行没有实例化"
        )
        #expect(abs(firstCell.frame.width - clipWidth) < 1, "单元格没有铺满表格宽度")

        let interactionHosts = OffscreenHost.allSubviews(of: host).compactMap { $0 as? RowInteractionHost.HostView }
        #expect(interactionHosts.contains { $0.bounds.width > 100 }, "整行没有交互宿主，单击选不中")

        #expect(context.navigationState.fullyVisibleFirstIndex == 0, "首屏可见行起点不对")
    }

    @Test("确认弹窗压着时列表停掉滚动，关掉后恢复")
    func confirmationBlocksListScrolling() async throws {
        let harness = try ClipboardHarness()
        let rows = (0..<10).map { HistoryRow.stub(title: "第 \($0) 行") }
        let store = HistoryListStore(
            repository: FakeHistoryRepository(rowsByQuery: ["": rows]),
            events: ClipboardHistoryEventBus()
        )
        await store.loadLatestAndWait()

        let context = PanelContext(manager: harness.manager, store: store, caches: PanelCaches())
        let view = AnyView(
            ClipboardListView(context: context)
                .environment(context)
                .environment(\.locale, RuntimeLanguage.shared.locale)
                .environment(RuntimeLanguage.shared)
        )
        let (host, window) = OffscreenHost.make(view, size: ClipboardLayout.panelSize)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "列表没建出滚动视图")
        let listScrollView = try #require(
            scrollView as? ListScrollView,
            "列表容器不是自定义滚动视图，确认弹窗压着时挡不住滚轮"
        )
        #expect(!listScrollView.isScrollBlocked, "默认就该能滚")

        context.confirmationState.isClearingHistory = true
        #expect(await Wait.until { listScrollView.isScrollBlocked }, "确认弹窗压着时没有停掉列表滚动")

        context.confirmationState.isClearingHistory = false
        #expect(await Wait.until { !listScrollView.isScrollBlocked }, "关掉确认弹窗后没有恢复列表滚动")

        context.confirmationState.pendingDeletionID = UUID()
        #expect(await Wait.until { listScrollView.isScrollBlocked }, "删除确认压着时也要停掉列表滚动")

        context.confirmationState.pendingDeletionID = nil
        #expect(await Wait.until { !listScrollView.isScrollBlocked }, "关掉删除确认后没有恢复列表滚动")
    }
}
