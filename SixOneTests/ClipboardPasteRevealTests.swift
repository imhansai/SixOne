//
//  ClipboardPasteRevealTests.swift
//  SixOneTests
//  粘贴置顶后须等它真的到第 0 行再揭示，重开面板时整条可见。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("粘贴置顶后的揭示")
@MainActor
struct ClipboardPasteRevealTests {
    private static let rowCount = 40

    private struct Fixture {
        let host: NSHostingView<AnyView>
        let window: NSWindow
        let context: PanelContext
        let store: HistoryListStore
        let events: ClipboardHistoryEventBus
        let rows: [HistoryRow]
    }

    private func makeFixture() async throws -> Fixture {
        let harness = try ClipboardHarness()
        let rows = (0..<Self.rowCount).map { HistoryRow.stub(title: "第 \($0) 行") }
        let events = ClipboardHistoryEventBus()
        let store = HistoryListStore(
            repository: FakeHistoryRepository(rowsByQuery: ["": rows]),
            events: events
        )
        await store.loadLatestAndWait()

        let context = PanelContext(
            manager: harness.manager,
            store: store,
            caches: PanelCaches()
        )
        let (host, window) = OffscreenHost.make(
            AnyView(
                ClipboardListView(context: context)
                    .environment(context)
                    .environment(\.locale, RuntimeLanguage.shared.locale)
                    .environment(RuntimeLanguage.shared)
            ),
            size: ClipboardLayout.panelSize
        )
        return Fixture(
            host: host,
            window: window,
            context: context,
            store: store,
            events: events,
            rows: rows
        )
    }

    private func makeReadyFixture() async throws -> (fixture: Fixture, scrollView: NSScrollView, tableView: NSTableView) {
        let fixture = try await makeFixture()
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: fixture.host), "没找到列表滚动视图")
        fixture.host.layoutSubtreeIfNeeded()
        let tableView = try #require(scrollView.documentView as? NSTableView)
        let rowsReady = await Wait.until { tableView.numberOfRows == Self.rowCount }
        #expect(rowsReady, "行没有落进表格")
        return (fixture, scrollView, tableView)
    }

    private func selectBottomSliverRow(
        _ fixture: Fixture,
        scrollView: NSScrollView
    ) async throws -> (id: UUID, anchorID: UUID, origin: CGFloat) {
        let touchedRow = fixture.rows[8]
        fixture.context.navigationState.selectedItemID = touchedRow.id
        fixture.context.navigationState.isSelectionActive = true
        fixture.context.navigationState.requestScroll(toRow: touchedRow.id)
        await Wait.until { scrollView.contentView.bounds.origin.y > 1 }
        await Wait.until { fixture.context.navigationState.fullyVisibleFirstIndex == 1 }
        let anchorID = fixture.store.rows[fixture.context.navigationState.fullyVisibleFirstIndex].id
        #expect(anchorID == fixture.rows[1].id, "前置现场不对：第 0 行没有被裁")
        return (touchedRow.id, anchorID, scrollView.contentView.bounds.origin.y)
    }

    @Test("粘贴置顶后重开面板：刚粘贴的那一条整条可见")
    func pastedItemFullyVisibleAfterReopen() async throws {
        let (fixture, scrollView, tableView) = try await makeReadyFixture()
        defer { fixture.window.orderOut(nil) }
        let (touchedID, anchorID, revealOrigin) = try await selectBottomSliverRow(fixture, scrollView: scrollView)
        #expect(revealOrigin > 1)

        fixture.context.navigationState.requestRevealAfterStoreChange(id: touchedID)
        fixture.window.orderOut(nil)
        fixture.events.post(.touched(id: touchedID))
        await Wait.until { fixture.store.rows.first?.id == touchedID }

        fixture.window.orderFrontRegardless()
        fixture.context.navigationState.requestScroll(toRow: anchorID)
        await Wait.until { scrollView.contentView.bounds.origin.y <= 0.5 }

        #expect(
            scrollView.documentVisibleRect.contains(tableView.rect(ofRow: 0)),
            "重开后面板里刚粘贴的那条被上边缘裁掉了（原点 \(scrollView.contentView.bounds.origin.y)）"
        )
    }

    @Test("置顶还没落定时，先到的其它数据变化不消耗揭示请求")
    func unrelatedRevisionDoesNotConsumeReveal() async throws {
        let (fixture, scrollView, tableView) = try await makeReadyFixture()
        defer { fixture.window.orderOut(nil) }
        let (touchedID, _, _) = try await selectBottomSliverRow(fixture, scrollView: scrollView)

        fixture.context.navigationState.requestRevealAfterStoreChange(id: touchedID)
        // 缩略图刷新不算置顶落定，揭示请求应保留。
        let revision = fixture.store.dataRevision
        fixture.events.post(.thumbnailUpdated(id: touchedID))
        await Wait.until { fixture.store.dataRevision != revision }
        #expect(
            scrollView.contentView.bounds.origin.y > 1,
            "揭示请求被不相干的数据变化提前消耗了"
        )
        #expect(fixture.context.navigationState.pendingRevealItemID == touchedID, "揭示请求不该被清掉")

        fixture.events.post(.touched(id: touchedID))
        await Wait.until { scrollView.contentView.bounds.origin.y <= 0.5 }
        #expect(scrollView.documentVisibleRect.contains(tableView.rect(ofRow: 0)))
    }

    @Test("复制反馈也会等置顶落定后揭示")
    func copyFeedbackStillReveals() async throws {
        let (fixture, scrollView, tableView) = try await makeReadyFixture()
        defer { fixture.window.orderOut(nil) }
        let (touchedID, _, _) = try await selectBottomSliverRow(fixture, scrollView: scrollView)

        fixture.context.copyState.itemID = touchedID
        await Wait.until { fixture.context.navigationState.pendingRevealItemID == touchedID }
        fixture.events.post(.touched(id: touchedID))
        await Wait.until { scrollView.contentView.bounds.origin.y <= 0.5 }
        #expect(scrollView.documentVisibleRect.contains(tableView.rect(ofRow: 0)))
    }
}
