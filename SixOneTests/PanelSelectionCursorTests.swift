//
//  PanelSelectionCursorTests.swift
//  SixOneTests

import Foundation
import Testing
@testable import SixOne

/// 选中移动与预览跟随；预览切不过去时必须回滚选中，避免界面错位。
@Suite("列表选中游标")
@MainActor
struct PanelSelectionCursorTests {
    @Test("尚无选中时：向下落最新一条，向上不动")
    func unselectedOnlyMovesDown() async throws {
        let env = try await makeEnv(Self.threeTextItems())

        env.cursor.move(direction: 1)
        #expect(env.cursor.selectedItemID == env.store.rows.first?.id)

        env.cursor.selectedItemID = nil
        _ = env.navigation.takePendingScrollCommands()
        env.cursor.move(direction: -1)
        #expect(env.cursor.selectedItemID == nil)
        #expect(env.navigation.takePendingScrollCommands().isEmpty)
    }

    @Test("窗口两端钳制，不越界")
    func clampsAtWindowBounds() async throws {
        let env = try await makeEnv(Self.threeTextItems())

        env.cursor.move(to: 0)
        env.cursor.move(direction: -1)
        #expect(env.cursor.selectedItemID == env.store.rows.first?.id)

        env.cursor.move(to: env.store.rows.count - 1)
        env.cursor.move(direction: 1)
        #expect(env.cursor.selectedItemID == env.store.rows.last?.id)
    }

    @Test("边界上重复按 ↑/↓ 不再发滚动请求")
    func boundaryDoesNotRequestScroll() async throws {
        let env = try await makeEnv(Self.threeTextItems())

        env.cursor.move(to: 0)
        _ = env.navigation.takePendingScrollCommands()
        env.cursor.move(direction: -1)
        #expect(env.navigation.takePendingScrollCommands().isEmpty, "首行再按 ↑ 不该请求滚动")

        env.cursor.move(to: env.store.rows.count - 1)
        _ = env.navigation.takePendingScrollCommands()
        env.cursor.move(direction: 1)
        #expect(env.navigation.takePendingScrollCommands().isEmpty, "末行再按 ↓ 不该请求滚动")

        // 已在端点时 ⌘↓ 仍须记录按键，供视图播放系统提示音。
        env.cursor.jumpToOldest()
        let commands = env.navigation.takePendingScrollCommands()
        #expect(commands.count == 1, "端点上的 ⌘↓ 应该请求一次")
        #expect(commands.last?.isEndpointJump == true, "端点命令要带上 isEndpointJump")
        #expect(commands.last?.isSelectionAlreadyAtEndpoint == true, "选中已在端点时也要记下来（用于提示音）")
        #expect(commands.last?.target == .row(env.store.rows.last!.id))
    }

    @Test("⌘↓ 跳到最旧一条并请求滚动过去")
    func jumpsToOldest() async throws {
        let env = try await makeEnv(Self.threeTextItems())

        env.cursor.jumpToOldest()

        #expect(env.cursor.selectedItemID == env.store.rows.last?.id)
        #expect(
            env.navigation.takePendingScrollCommands().last?.target
                == .row(env.store.rows.last!.id)
        )
    }

    @Test("预览内 ↑/↓：选中与预览一起切到相邻条目")
    func previewFollowsSelection() async throws {
        let env = try await makeEnv(Self.threeTextItems())
        let anchor = env.store.rows[1]
        env.previewState.item = env.manager.fetchFullItem(id: anchor.id)

        env.cursor.stepPreview(direction: 1)
        #expect(env.cursor.selectedItemID == env.store.rows[2].id)
        #expect(env.previewState.item?.id == env.store.rows[2].id)

        env.cursor.stepPreview(direction: -1)
        #expect(env.cursor.selectedItemID == anchor.id)
        #expect(env.previewState.item?.id == anchor.id)
    }

    @Test("相邻条目打不开预览时，选中与滚动回滚到锚点")
    func rollsBackWhenPreviewSwitchFails() async throws {
        let missingFile = ClipboardItem(
            kind: .file,
            filePath: "/definitely/not/here-\(UUID().uuidString).txt"
        )
        let anchor = ClipboardItem(kind: .text, text: "锚点")
        let env = try await makeEnv([missingFile, anchor])
        #expect(env.store.rows.first?.id == anchor.id)

        env.previewState.item = env.manager.fetchFullItem(id: anchor.id)
        env.cursor.stepPreview(direction: 1)

        #expect(env.cursor.selectedItemID == anchor.id)
        #expect(env.previewState.item?.id == anchor.id)
        #expect(
            env.navigation.takePendingScrollCommands().last?.target
                == .row(anchor.id)
        )
    }

    @Test("相邻条目是文件组时：不切入组预览，选中回滚到锚点")
    func rollsBackWhenNeighbourIsFileGroup() async throws {
        let group = ClipboardItem(kind: .file, filePaths: ["/tmp/a.txt", "/tmp/b.txt"])
        let anchor = ClipboardItem(kind: .text, text: "锚点")
        let env = try await makeEnv([group, anchor])
        #expect(env.store.rows.first?.id == anchor.id)

        env.previewState.item = env.manager.fetchFullItem(id: anchor.id)
        env.cursor.stepPreview(direction: 1)

        #expect(env.cursor.selectedItemID == anchor.id)
        #expect(env.previewState.item?.id == anchor.id)
        #expect(
            env.navigation.takePendingScrollCommands().last?.target
                == .row(anchor.id)
        )
    }

    @Test("锚点不在当前窗口里时，预览导航不移动选中")
    func ignoresStepWhenAnchorNotInWindow() async throws {
        let env = try await makeEnv(Self.threeTextItems())
        env.previewState.item = ClipboardItem(kind: .text, text: "不在窗口里")

        env.cursor.stepPreview(direction: 1)

        #expect(env.cursor.selectedItemID == nil)
        #expect(env.navigation.takePendingScrollCommands().isEmpty)
    }

    // MARK: - 夹具

    private static func threeTextItems() -> [ClipboardItem] {
        ["第一", "第二", "第三"].map { ClipboardItem(kind: .text, text: $0) }
    }

    /// 预览切换按 id 取整条，所以用真库。
    private func makeEnv(_ items: [ClipboardItem]) async throws -> Env {
        let harness = try ClipboardHarness()
        for item in items {
            harness.context.insert(item)
        }
        try harness.context.save()

        let store = HistoryListStore(
            repository: SwiftDataHistoryRepository(container: harness.container),
            events: ClipboardHistoryEventBus()
        )
        await store.loadLatestAndWait()

        let navigation = NavigationState()
        let previewState = PreviewState()
        let launcher = PreviewLauncher(
            manager: harness.manager,
            previewState: previewState,
            noticeState: NoticeState()
        )
        let cursor = PanelSelectionCursor(
            store: store,
            navigationState: navigation,
            previewState: previewState,
            previewLauncher: launcher
        )
        return Env(
            manager: harness.manager,
            store: store,
            navigation: navigation,
            previewState: previewState,
            cursor: cursor
        )
    }

    @MainActor
    private struct Env {
        let manager: ClipboardManager
        let store: HistoryListStore
        let navigation: NavigationState
        let previewState: PreviewState
        let cursor: PanelSelectionCursor
    }
}
