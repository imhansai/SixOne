//
//  QuickPasteHintStateTests.swift
//  SixOneTests
//  按住 ⌘ 的编号提示：延时出现、松开即收、非 ⌘/⌘⇧ 组合不出现。
//

import AppKit
import Testing
@testable import SixOne

@Suite("快速粘贴编号提示")
@MainActor
struct QuickPasteHintStateTests {
    @Test("按住 ⌘ 延时后显示，松开立即收起")
    func showsAfterDelayThenCancels() async {
        let state = QuickPasteHintState(showDelay: 0)
        state.handleModifiers(.command)
        #expect(!state.isShowing, "按下瞬间不该闪出编号")

        #expect(await Wait.until { state.isShowing })

        state.handleModifiers([])
        #expect(!state.isShowing)
    }

    @Test("⌘⇧ 同样显示；加上 ⌥ 立即收起")
    func modifierVariants() async {
        let state = QuickPasteHintState(showDelay: 0)
        state.handleModifiers([.command, .shift])
        #expect(await Wait.until { state.isShowing })

        state.handleModifiers([.command, .option])
        #expect(!state.isShowing)
    }

    @Test("延时内取消后不再显示")
    func cancelBeforeDelay() async {
        let state = QuickPasteHintState(showDelay: 0.05)
        state.handleModifiers(.command)
        state.cancel()

        await Wait.settle(milliseconds: 120)
        #expect(!state.isShowing)
    }
}
