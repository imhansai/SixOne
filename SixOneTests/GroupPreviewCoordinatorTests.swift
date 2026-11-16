//
//  GroupPreviewCoordinatorTests.swift
//  SixOneTests
//

import AppKit
import Testing
@testable import SixOne

@Suite("文件组预览策略")
@MainActor
struct GroupPreviewCoordinatorTests {
    private let paths = ["/tmp/a.txt", "/tmp/b.txt"]

    private func makeItem() -> ClipboardItem {
        ClipboardItem(kind: .file, filePaths: paths)
    }

    private func makeState(item: ClipboardItem, urls: [URL?]) -> PreviewState {
        let state = PreviewState()
        state.item = item
        state.scopedGroupURLs = urls.map { $0.map { ScopedFileURL(url: $0, needsStop: false) } }
        return state
    }

    private func makeCoordinator(
        item: ClipboardItem,
        urls: [URL?],
        state: PreviewState,
        actions: FakeGroupActions? = nil,
        shell: FakeShellActions? = nil,
        openURL: @escaping (URL) -> Void = { _ in },
        revealURL: @escaping (URL) -> Void = { _ in }
    ) -> GroupPreviewCoordinator {
        GroupPreviewCoordinator(
            item: item,
            groupURLs: urls,
            previewState: state,
            groupActions: actions,
            shellActions: shell,
            openURL: openURL,
            revealURL: revealURL
        )
    }

    @Test("条目按原始下标映射路径与 URL")
    func entries() {
        let item = makeItem()
        let urls = [URL(fileURLWithPath: paths[0]), nil]
        let state = makeState(item: item, urls: urls)
        let coordinator = makeCoordinator(item: item, urls: urls, state: state)

        #expect(coordinator.entries.map(\.name) == ["a.txt", "b.txt"])
        #expect(coordinator.entries[0].url == urls[0])
        #expect(coordinator.entries[1].url == nil)
        #expect(coordinator.visibleEntries.map(\.index) == [0, 1])
    }

    @Test("筛选后可见集保持组内原始下标")
    func filteredEntries() {
        let item = makeItem()
        let urls = [URL(fileURLWithPath: paths[0]), nil]
        let state = makeState(item: item, urls: urls)
        let coordinator = makeCoordinator(item: item, urls: urls, state: state)

        state.setGroupFilterText("b")
        #expect(coordinator.visibleEntries.map(\.index) == [1])
    }

    @Test("总览与单文件切换决定查看下标；URL 缺失时回到总览")
    func viewingIndex() {
        let item = makeItem()
        let urls = [URL(fileURLWithPath: paths[0]), URL(fileURLWithPath: paths[1])]
        let state = makeState(item: item, urls: urls)
        let coordinator = makeCoordinator(item: item, urls: urls, state: state)

        state.showGroupFile(1)
        #expect(coordinator.viewingIndex == 1)
        state.showGroupOverview()
        #expect(coordinator.viewingIndex == nil)

        let shortURLs = [URL(fileURLWithPath: paths[0])]
        let shortState = makeState(item: item, urls: shortURLs)
        shortState.showGroupFile(1)
        let shortCoordinator = makeCoordinator(item: item, urls: shortURLs, state: shortState)
        #expect(shortCoordinator.viewingIndex == nil)
    }

    @Test("选择、预览、分享与范围发布回写状态")
    func actions() {
        let item = makeItem()
        let urls = [URL(fileURLWithPath: paths[0]), URL(fileURLWithPath: paths[1])]
        let state = makeState(item: item, urls: urls)
        let actions = FakeGroupActions()
        let shell = FakeShellActions()
        let coordinator = makeCoordinator(
            item: item, urls: urls, state: state, actions: actions, shell: shell
        )

        coordinator.select(1)
        #expect(state.groupSelectedIndex == 1)
        #expect(shell.focusRequests == 1)

        coordinator.preview(0)
        #expect(state.groupFileIndex == 0)

        let anchor = NSView()
        coordinator.share(1, anchorView: anchor)
        #expect(actions.fileShares.map { $0.0 } == [1])

        coordinator.visibleRangeDidChange(0...1)
        #expect(state.groupVisibleRowRange == 0...1)

        state.item = ClipboardItem(kind: .file, filePaths: paths)
        coordinator.visibleRangeDidChange(1...1)
        #expect(state.groupVisibleRowRange == 0...1, "异组迟到的范围不写入")
    }

    @Test("打开与访达只在 URL 存在时触发并交棒")
    func openAndReveal() {
        let item = makeItem()
        let urls = [URL(fileURLWithPath: paths[0]), nil]
        let state = makeState(item: item, urls: urls)
        let shell = FakeShellActions()
        var opened: [URL] = []
        var revealed: [URL] = []
        let coordinator = makeCoordinator(
            item: item,
            urls: urls,
            state: state,
            shell: shell,
            openURL: { opened.append($0) },
            revealURL: { revealed.append($0) }
        )

        coordinator.handle(.open, index: 0)
        #expect(opened.count == 1)
        #expect(shell.handOffs == 1)

        coordinator.handle(.open, index: 1)
        #expect(opened.count == 1)

        coordinator.handle(.reveal, index: 0)
        #expect(revealed.count == 1)
        #expect(shell.handOffs == 2)
    }

    @Test("粘贴与复制交给面板动作")
    func pasteAndCopy() {
        let item = makeItem()
        let urls = [URL(fileURLWithPath: paths[0]), nil]
        let state = makeState(item: item, urls: urls)
        let actions = FakeGroupActions()
        let coordinator = makeCoordinator(item: item, urls: urls, state: state, actions: actions)

        coordinator.handle(.paste, index: 1)
        coordinator.handle(.copy, index: 0)

        #expect(actions.commands.map { $0.0 } == [.paste, .copy])
        #expect(actions.commands.map { $0.1 } == [1, 0])
    }
}

private final class FakeGroupActions: GroupActionHandling {
    var commands: [(GroupFileCommand, Int)] = []
    var fileShares: [(Int, NSView)] = []
    var groupShares: [NSView?] = []

    func panelDidRequestGroupFileShare(at index: Int, anchorView: NSView) {
        fileShares.append((index, anchorView))
    }

    func panelDidRequestShareGroup(anchorView: NSView?) {
        groupShares.append(anchorView)
    }

    func panelDidInvokeGroupFileCommand(_ command: GroupFileCommand, index: Int) {
        commands.append((command, index))
    }
}

private final class FakeShellActions: ShellActionHandling {
    var canRequestSettings = false
    var focusRequests = 0
    var handOffs = 0

    func panelDidRequestSettings() {}
    func panelDidRequestFocusContent() { focusRequests += 1 }
    func panelDidHandOffToExternalApp() { handOffs += 1 }
    func panelDidRequestClearHistory() {}
}
