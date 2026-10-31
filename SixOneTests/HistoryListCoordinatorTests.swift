//
//  HistoryListCoordinatorTests.swift
//  SixOneTests
//  列表会话协调：选中、预览关闭收尾、置顶揭示与复制反馈。
//

import Foundation
import Testing
@testable import SixOne

@Suite("列表会话协调")
@MainActor
struct HistoryListCoordinatorTests {
    @Test("选中项离开窗口后摘掉选中")
    func discardsOrphanedSelection() async throws {
        let fixture = try await makeFixture()
        fixture.context.navigationState.selectedItemID = UUID()
        fixture.context.navigationState.isSelectionActive = true

        fixture.coordinator.handleDataRevisionChange()

        #expect(fixture.context.navigationState.selectedItemID == nil)
        #expect(!fixture.context.navigationState.isSelectionActive)
    }

    @Test("选中项仍在窗口内时保留选中")
    func keepsSelectionInWindow() async throws {
        let fixture = try await makeFixture()
        let selected = fixture.rows[1].id
        fixture.context.navigationState.selectedItemID = selected
        fixture.context.navigationState.isSelectionActive = true

        fixture.coordinator.handleDataRevisionChange()

        #expect(fixture.context.navigationState.selectedItemID == selected)
        #expect(fixture.context.navigationState.isSelectionActive)
    }

    @Test("窗口外预览条目被删除后关闭预览")
    func closesDeletedPreview() async throws {
        let fixture = try await makeFixture()
        fixture.context.previewState.item = makePreviewItem(id: UUID())

        fixture.coordinator.handleDataRevisionChange()

        #expect(await Wait.until { fixture.context.previewState.item == nil })
    }

    @Test("窗口外预览仍在库里时保留，连续数据变化只探测一次")
    func keepsExistingPreviewAndCoalescesProbe() async throws {
        let fixture = try await makeFixture()
        let preview = HistoryRow.stub(title: "窗口外预览")
        await fixture.repository.setRows(fixture.rows + [preview], for: "")
        await fixture.repository.setRowDelay(.milliseconds(200), for: preview.id)
        fixture.context.previewState.item = makePreviewItem(id: preview.id)

        fixture.coordinator.handleDataRevisionChange()
        fixture.coordinator.handleDataRevisionChange()

        #expect(await Wait.untilAsync { await fixture.repository.itemExistsRequestCount() == 1 })
        #expect(await fixture.repository.waitUntilRowsReturned(1))
        #expect(fixture.context.previewState.item != nil)
    }

    @Test("编辑保存后关闭预览，滚回该条目")
    func previewClosedAfterEditScrollsToItem() async throws {
        let fixture = try await makeFixture()
        let row = fixture.rows[1]
        fixture.context.previewState.item = makePreviewItem(id: row.id)
        fixture.coordinator.markPreviewEdited()

        fixture.coordinator.handlePreviewIDChange(from: row.id, to: nil)

        #expect(fixture.context.navigationState.takePendingScrollCommands().map(\.target) == [.row(row.id)])
    }

    @Test("未编辑就关闭预览不额外滚动")
    func previewClosedWithoutEditDoesNotScroll() async throws {
        let fixture = try await makeFixture()
        let row = fixture.rows[1]
        fixture.context.previewState.item = makePreviewItem(id: row.id)

        fixture.coordinator.handlePreviewIDChange(from: row.id, to: nil)

        #expect(fixture.context.navigationState.takePendingScrollCommands().isEmpty)
    }

    @Test("预览条目已不在结果中时清选中并回顶部")
    func previewClosedOutsideWindowClearsSelectionAndScrollsTop() async throws {
        let fixture = try await makeFixture()
        let missing = UUID()
        fixture.context.navigationState.selectedItemID = missing
        fixture.context.navigationState.isSelectionActive = true

        fixture.coordinator.handlePreviewIDChange(from: missing, to: nil)

        #expect(fixture.context.navigationState.selectedItemID == nil)
        #expect(!fixture.context.navigationState.isSelectionActive)
        #expect(fixture.context.navigationState.takePendingScrollCommands().map(\.target) == [.top])
    }

    @Test("置顶条目到达首行后滚进视野")
    func revealsTouchedItemAtTop() async throws {
        let fixture = try await makeFixture()
        let first = fixture.rows[0].id
        fixture.context.navigationState.requestRevealAfterStoreChange(id: first)

        fixture.coordinator.handleDataRevisionChange()

        #expect(fixture.context.navigationState.pendingRevealItemID == nil)
        #expect(fixture.context.navigationState.takePendingScrollCommands().map(\.target) == [.row(first)])
    }

    @Test("揭示目标已离开窗口时放弃")
    func dropsRevealWhenItemLeftWindow() async throws {
        let fixture = try await makeFixture()
        fixture.context.navigationState.requestRevealAfterStoreChange(id: UUID())

        fixture.coordinator.handleDataRevisionChange()

        #expect(fixture.context.navigationState.pendingRevealItemID == nil)
        #expect(fixture.context.navigationState.takePendingScrollCommands().isEmpty)
    }

    @Test("选中条目时收起输入焦点并请求滚入视野")
    func selectResignsFocusAndRequestsScroll() async throws {
        let fixture = try await makeFixture()
        fixture.context.searchState.isFocused = true
        fixture.context.moreActionsState.isFocused = true
        let row = fixture.rows[2]

        fixture.coordinator.select(id: row.id)

        #expect(fixture.context.navigationState.selectedItemID == row.id)
        #expect(fixture.context.navigationState.isSelectionActive)
        #expect(!fixture.context.searchState.isFocused)
        #expect(!fixture.context.moreActionsState.isFocused)
        #expect(fixture.context.navigationState.takePendingScrollCommands().map(\.target) == [.row(row.id)])
    }

    @Test("复制条目会请求揭示并点亮复制反馈")
    func copyWithFeedbackRequestsReveal() async throws {
        let fixture = try await makeFixture()
        let row = fixture.rows[0]

        fixture.coordinator.copyWithFeedback(id: row.id)

        #expect(fixture.context.navigationState.pendingRevealItemID == row.id)
        #expect(fixture.context.copyState.feedbackItemID == row.id)
    }

    // MARK: - 夹具

    private struct Fixture {
        let context: PanelContext
        let store: HistoryListStore
        let repository: FakeHistoryRepository
        let coordinator: HistoryListCoordinator
        let rows: [HistoryRow]
    }

    private func makeFixture(rowCount: Int = 3) async throws -> Fixture {
        let rows = (0..<rowCount).map { HistoryRow.stub(title: "第 \($0) 行") }
        let repository = FakeHistoryRepository(rowsByQuery: ["": rows])
        let store = HistoryListStore(repository: repository, events: ClipboardHistoryEventBus())
        await store.loadLatestAndWait()

        let harness = try ClipboardHarness()
        let context = PanelContext(manager: harness.manager, store: store, caches: PanelCaches())
        return Fixture(
            context: context,
            store: store,
            repository: repository,
            coordinator: HistoryListCoordinator(context: context),
            rows: rows
        )
    }

    private func makePreviewItem(id: UUID) -> ClipboardItem {
        let item = ClipboardItem(kind: .text, text: "预览")
        item.id = id
        item.recencyID = id
        return item
    }
}
