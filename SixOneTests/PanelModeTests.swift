//
//  PanelModeTests.swift
//  SixOneTests

import Testing
@testable import SixOne

@Suite("面板导航层级")
@MainActor
struct PanelModeTests {
    @Test("没有预览时是历史列表")
    func historyList() {
        #expect(PreviewState().mode == .historyList)
    }

    @Test("普通条目与单文件条目都是条目预览")
    func itemPreview() {
        let state = PreviewState()
        let text = ClipboardItem(kind: .text, text: "x")
        state.item = text
        #expect(state.mode == .itemPreview(id: text.id))

        let single = ClipboardItem(kind: .file, filePaths: ["/tmp/a"])
        state.item = single
        #expect(state.mode == .itemPreview(id: single.id))
    }

    @Test("多文件条目在总览与单文件之间切换")
    func groupModes() {
        let state = PreviewState()
        let group = ClipboardItem(kind: .file, filePaths: ["/tmp/a", "/tmp/b"])
        state.item = group
        #expect(state.mode == .groupOverview(itemID: group.id))
        #expect(state.isGroupOverview)

        state.showGroupFile(1)
        #expect(state.mode == .groupFile(itemID: group.id, index: 1))
        #expect(!state.isGroupOverview)

        state.showGroupOverview()
        #expect(state.mode == .groupOverview(itemID: group.id))
        #expect(state.mode.isGroupPreview)
    }
}
