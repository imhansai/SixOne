//
//  PanelSearchSessionTests.swift
//  SixOneTests
//  搜索词到库查询的契约：防抖、换词回顶、Esc 清空与唤出对齐。

import Foundation
import Testing
@testable import SixOne

@Suite("搜索管道")
@MainActor
struct PanelSearchSessionTests {
    private struct Fixture {
        let session: PanelSearchSession
        let store: HistoryListStore
        let searchState: SearchState
        let navigationState: NavigationState
        let repository: FakeHistoryRepository
    }

    private func makeFixture() -> Fixture {
        let repository = FakeHistoryRepository(rowsByQuery: [
            "": [HistoryRow.stub(title: "全部")],
            "abc": [HistoryRow.stub(title: "命中")],
        ])
        let store = HistoryListStore(repository: repository, events: ClipboardHistoryEventBus())
        let searchState = SearchState()
        let navigationState = NavigationState()
        let session = PanelSearchSession(
            store: store,
            searchState: searchState,
            navigationState: navigationState,
            debouncer: SearchDebouncer(delay: 0.02)
        )
        return Fixture(
            session: session,
            store: store,
            searchState: searchState,
            navigationState: navigationState,
            repository: repository
        )
    }

    @Test("连打只在停手后交付一次查询")
    func debouncesTyping() async throws {
        let fixture = makeFixture()
        for text in ["a", "ab", "abc"] {
            fixture.searchState.text = text
            fixture.session.textDidChange()
        }
        #expect(fixture.store.query == "", "防抖期内不该落库")

        let landed = await Wait.until { fixture.store.query == "abc" }
        #expect(landed)
        // 先落 query 再排后台读，等本次读落定才数得准查询次数。
        await fixture.store.waitForPendingLoad()
        let queries = await fixture.repository.requestedQueries
        #expect(queries == ["abc"], "中间那两次输入不该各发一次查询")
    }

    @Test("换查询先清选中并回顶：结果会整份换掉")
    func resetsSelectionBeforeSwitchingQuery() async throws {
        let fixture = makeFixture()
        fixture.navigationState.selectedItemID = UUID()
        fixture.navigationState.isSelectionActive = true

        fixture.searchState.text = "abc"
        fixture.session.textDidChange()

        #expect(fixture.navigationState.selectedItemID == nil)
        #expect(!fixture.navigationState.isSelectionActive)
        #expect(
            fixture.navigationState.takePendingScrollCommands().last?.target == .top
        )
    }

    @Test("切换分组立即清选中并回顶，保留搜索词")
    func collectionChangeResetsSelectionAndKeepsSearchText() async throws {
        let fixture = makeFixture()
        fixture.searchState.text = "abc"
        fixture.session.textDidChange()
        await Wait.until { fixture.store.query == "abc" }
        fixture.navigationState.selectedItemID = UUID()
        fixture.navigationState.isSelectionActive = true
        _ = fixture.navigationState.takePendingScrollCommands()

        let collectionID = UUID()
        fixture.session.filterDidChange(
            fixture.store.filter.toggled(collectionID: collectionID)
        )

        #expect(fixture.navigationState.selectedItemID == nil)
        #expect(!fixture.navigationState.isSelectionActive)
        #expect(
            fixture.navigationState.takePendingScrollCommands().last?.target == .top
        )
        #expect(fixture.store.filter.collections == [collectionID])
        #expect(fixture.store.query == "abc", "切换分组不该清掉搜索词")
        await fixture.store.waitForPendingLoad()
    }

    @Test("取消分组筛选：保留搜索词并回到全部数据")
    func clearingCollectionFilterKeepsSearchText() async throws {
        let fixture = makeFixture()
        fixture.searchState.text = "abc"
        fixture.session.textDidChange()
        await Wait.until { fixture.store.query == "abc" }
        await fixture.store.waitForPendingLoad()

        let collectionID = UUID()
        fixture.session.filterDidChange(
            fixture.store.filter.toggled(collectionID: collectionID)
        )
        await fixture.store.waitForPendingLoad()
        #expect(fixture.store.filter.collections == [collectionID])

        // 再点一次同一分组：取消筛选，搜索词不动。
        fixture.session.filterDidChange(
            fixture.store.filter.toggled(collectionID: collectionID)
        )
        await fixture.store.waitForPendingLoad()
        #expect(fixture.store.filter.collections.isEmpty)
        #expect(fixture.store.query == "abc", "取消筛选不该清掉搜索词")
    }

    @Test("Esc 清空立即落库，不等防抖")
    func clearAppliesImmediately() async throws {
        let fixture = makeFixture()
        fixture.searchState.text = "abc"
        fixture.session.textDidChange()
        await Wait.until { fixture.store.query == "abc" }
        await fixture.store.waitForPendingLoad()

        fixture.session.clear()

        #expect(fixture.searchState.text == "")
        #expect(fixture.store.query == "", "清空就地把查询词换回全部历史")
    }

    @Test("清空后视图侧再报一次文本变化，不重复落库")
    func clearAbsorbsFollowUpTextChange() async throws {
        let fixture = makeFixture()
        fixture.searchState.text = "abc"
        fixture.session.textDidChange()
        await Wait.until { fixture.store.query == "abc" }

        fixture.session.clear()
        fixture.session.textDidChange()   // 视图侧 onChange 随后还会报一次
        await fixture.store.waitForPendingLoad()

        let queries = await fixture.repository.requestedQueries
        #expect(queries == ["abc", ""], "重复触发不该再发一次查询")
    }

    @Test("面板唤出：输入框里的词与当前查询对齐")
    func syncsInputToStoreOnShow() async throws {
        let fixture = makeFixture()
        // 收起期间防抖被取消：输入框有词，store 仍停在全部历史。
        fixture.searchState.text = "abc"

        fixture.session.syncToStore()

        #expect(fixture.store.query == "abc")
    }

    @Test("输入框里的词与当前查询一致时不动列表")
    func leavesListAloneWhenQueryMatches() async throws {
        let fixture = makeFixture()
        await fixture.store.loadLatestAndWait()

        fixture.session.syncToStore()
        await fixture.store.waitForPendingLoad()

        let queries = await fixture.repository.requestedQueries
        #expect(queries.count == 1, "与当前查询一致就不该再查一次")
    }

    @Test("定位清词：记住目标、清空搜索且不先回顶")
    func clearForLocationKeepsPendingAndSkipsTop() async throws {
        let fixture = makeFixture()
        fixture.searchState.text = "abc"
        fixture.session.textDidChange()
        await Wait.until { fixture.store.query == "abc" }
        await fixture.store.waitForPendingLoad()
        _ = fixture.navigationState.takePendingScrollCommands()

        let target = UUID()
        fixture.session.clearForLocation(id: target, rowsAbove: 2)

        #expect(fixture.searchState.text == "")
        #expect(fixture.store.query == "", "定位要先把搜索词清回全部历史")
        #expect(
            fixture.navigationState.pendingLocate
                == PendingHistoryLocation(itemID: target, rowsAbove: 2)
        )
        #expect(
            fixture.navigationState.takePendingScrollCommands().isEmpty,
            "定位前不该先回顶，避免闪一下再跳走"
        )
        await fixture.store.waitForPendingLoad()
    }

    @Test("定位清词后重新输入搜索词会作废待定位目标")
    func typingAfterLocationClearsPending() async throws {
        let fixture = makeFixture()
        fixture.searchState.text = "abc"
        fixture.session.textDidChange()
        await Wait.until { fixture.store.query == "abc" }
        await fixture.store.waitForPendingLoad()
        fixture.session.clearForLocation(id: UUID(), rowsAbove: 0)

        fixture.searchState.text = "xyz"
        fixture.session.textDidChange()

        #expect(fixture.navigationState.pendingLocate == nil)
        fixture.session.cancelPendingWork()
    }

    @Test("定位清词后换筛选会作废待定位目标")
    func filterChangeAfterLocationClearsPending() async throws {
        let fixture = makeFixture()
        fixture.searchState.text = "abc"
        fixture.session.textDidChange()
        await Wait.until { fixture.store.query == "abc" }
        await fixture.store.waitForPendingLoad()
        fixture.session.clearForLocation(id: UUID(), rowsAbove: 0)
        await fixture.store.waitForPendingLoad()

        fixture.session.filterDidChange(
            fixture.store.filter.toggled(kind: .text)
        )

        #expect(fixture.navigationState.pendingLocate == nil)
        await fixture.store.waitForPendingLoad()
    }
}
