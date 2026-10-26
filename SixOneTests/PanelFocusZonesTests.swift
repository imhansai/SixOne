//
//  PanelFocusZonesTests.swift
//  SixOneTests

import Foundation
import Testing
@testable import SixOne

@Suite("面板焦点循环")
@MainActor
struct PanelFocusZonesTests {
    private struct Fixture {
        let zones: PanelFocusZones
        let store: HistoryListStore
        let searchState: SearchState
        let moreActionsState: MoreActionsState
        let navigationState: NavigationState
    }

    private func makeFixture(fullKeyboardAccess: Bool = true) async throws -> Fixture {
        let harness = try ClipboardHarness()
        let store = HistoryListStore(
            repository: FakeHistoryRepository(rowsByQuery: ["": [
                HistoryRow.stub(title: "第一条"),
                HistoryRow.stub(title: "第二条"),
            ]]),
            events: ClipboardHistoryEventBus()
        )
        await store.loadLatestAndWait()

        let searchState = SearchState()
        let moreActionsState = MoreActionsState()
        let navigationState = NavigationState()
        let previewState = PreviewState()
        let cursor = PanelSelectionCursor(
            store: store,
            navigationState: navigationState,
            previewState: previewState,
            previewLauncher: PreviewLauncher(
                manager: harness.manager,
                previewState: previewState,
                noticeState: NoticeState()
            )
        )
        return Fixture(
            zones: PanelFocusZones(
                panel: PanelWindowFactory.makePanel(),
                searchState: searchState,
                moreActionsState: moreActionsState,
                navigationState: navigationState,
                cursor: cursor,
                isFullKeyboardAccessEnabled: { fullKeyboardAccess }
            ),
            store: store,
            searchState: searchState,
            moreActionsState: moreActionsState,
            navigationState: navigationState
        )
    }

    @Test("交出焦点：本来就不在焦点上时不再发失焦请求")
    func resignFocusIsInertWhenNotFocused() {
        let search = SearchState()
        search.resignFocus()
        #expect(search.blurRequestID == 0)

        search.isFocused = true
        search.resignFocus()
        search.resignFocus()
        #expect(!search.isFocused)
        #expect(search.blurRequestID == 1, "重复交出焦点不该反复发请求")
    }

    @Test("进搜索站：清掉更多操作的焦点，保留列表选中（只置灰）")
    func focusSearchKeepsSelection() async throws {
        let fixture = try await makeFixture()
        let selectedID = UUID()
        fixture.navigationState.selectedItemID = selectedID
        fixture.navigationState.isSelectionActive = true
        fixture.moreActionsState.isFocused = true

        fixture.zones.focusSearch()

        #expect(fixture.searchState.focusRequestID == 1)
        #expect(!fixture.moreActionsState.isFocused)
        #expect(fixture.navigationState.selectedItemID == selectedID)
        #expect(!fixture.navigationState.isSelectionActive, "选中要进入失焦置灰态")
    }

    @Test("进更多操作站：搜索框收到失焦请求，选中保留")
    func focusMoreActionsResignsSearch() async throws {
        let fixture = try await makeFixture()
        let selectedID = UUID()
        fixture.searchState.isFocused = true
        fixture.navigationState.selectedItemID = selectedID
        fixture.navigationState.isSelectionActive = true

        fixture.zones.focusMoreActions()

        #expect(!fixture.searchState.isFocused)
        #expect(fixture.searchState.blurRequestID == 1)
        #expect(fixture.moreActionsState.isFocused, "聚焦请求发出时就要同步置位，空格路由不能等视图回写")
        #expect(fixture.moreActionsState.focusRequestID == 1)
        #expect(fixture.navigationState.selectedItemID == selectedID)
        #expect(!fixture.navigationState.isSelectionActive)
    }

    @Test("进列表站：有选中就点亮，没有就落到第一条")
    func focusListActivatesSelection() async throws {
        let fixture = try await makeFixture()
        let selectedID = UUID()
        fixture.searchState.isFocused = true
        fixture.moreActionsState.isFocused = true
        fixture.navigationState.selectedItemID = selectedID

        fixture.zones.focusList()

        #expect(!fixture.searchState.isFocused)
        #expect(fixture.searchState.blurRequestID == 1)
        #expect(!fixture.moreActionsState.isFocused)
        #expect(fixture.navigationState.selectedItemID == selectedID)
        #expect(fixture.navigationState.isSelectionActive)

        let noSelection = try await makeFixture()
        noSelection.zones.focusList()
        #expect(noSelection.navigationState.selectedItemID == noSelection.store.rows.first?.id)
        #expect(noSelection.navigationState.isSelectionActive)
    }

    @Test("Tab 从列表出发按 搜索 → 更多操作 → 列表 前进")
    func cyclesForward() async throws {
        let fixture = try await makeFixture()

        fixture.zones.cycle(backwards: false)
        #expect(fixture.searchState.focusRequestID == 1)

        // 焦点落点由视图回写，这里显式模拟。
        fixture.searchState.isFocused = true
        fixture.zones.cycle(backwards: false)
        #expect(fixture.moreActionsState.focusRequestID == 1)

        fixture.moreActionsState.isFocused = true
        fixture.zones.cycle(backwards: false)
        #expect(fixture.navigationState.isSelectionActive, "回到列表要显示选中")
    }

    @Test("Shift+Tab 从列表反向走到更多操作，再到搜索")
    func cyclesBackwards() async throws {
        let fixture = try await makeFixture()

        fixture.zones.cycle(backwards: true)
        #expect(fixture.moreActionsState.focusRequestID == 1)

        fixture.moreActionsState.isFocused = true
        fixture.zones.cycle(backwards: true)
        #expect(fixture.searchState.focusRequestID == 1)
        #expect(!fixture.moreActionsState.isFocused)
    }

    @Test("完整键盘访问关闭：Tab 只在搜索与列表之间往返")
    func fullKeyboardAccessOffSkipsMoreActions() async throws {
        let fixture = try await makeFixture(fullKeyboardAccess: false)

        fixture.zones.cycle(backwards: false)
        #expect(fixture.searchState.focusRequestID == 1)

        fixture.searchState.isFocused = true
        fixture.zones.cycle(backwards: false)
        #expect(!fixture.moreActionsState.isFocused)
        #expect(fixture.navigationState.isSelectionActive)

        fixture.zones.cycle(backwards: true)
        #expect(fixture.searchState.focusRequestID == 2)

        fixture.moreActionsState.isFocused = true
        fixture.zones.cycle(backwards: false)
        #expect(fixture.navigationState.isSelectionActive)
        fixture.moreActionsState.isFocused = true
        fixture.zones.cycle(backwards: true)
        #expect(fixture.searchState.focusRequestID == 3)
    }
}
