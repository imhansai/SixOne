//
//  ShortcutRecorderTests.swift
//  SixOneTests

import AppKit
import Carbon.HIToolbox
import Testing
@testable import SixOne

@Suite("快捷键录制控件")
@MainActor
struct ShortcutRecorderTests {
    private func makeRecorder(
        onCapture: @escaping (NSEvent) -> Bool
    ) -> ShortcutRecorder.RecorderView {
        let view = ShortcutRecorder.RecorderView(
            frame: NSRect(x: 0, y: 0, width: 96, height: 26)
        )
        view.onCapture = onCapture
        return view
    }

    private func mouseDown() -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func keyEvent(
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }

    @Test("录制态下连键等价也捕获：⌘W 这类不会先被菜单截走")
    func capturesKeyEquivalentWhileRecording() {
        var captured: NSEvent?
        let view = makeRecorder { captured = $0; return true }

        view.mouseDown(with: mouseDown())
        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: kVK_ANSI_W, modifiers: .command, characters: "w")
        )

        #expect(handled, "录制时要吞掉该事件，别让它触发菜单（例如关闭窗口）")
        #expect(captured?.keyCode == UInt16(kVK_ANSI_W))
        #expect(captured?.modifierFlags == .command)
    }

    @Test("非录制态：键等价照常透传，控件不吞")
    func passesThroughKeyEquivalentWhenIdle() {
        var captured = false
        let view = makeRecorder { _ in captured = true; return true }

        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: kVK_ANSI_W, modifiers: .command, characters: "w")
        )

        #expect(!handled)
        #expect(!captured)
    }

    @Test("录制态：普通组合仍由 keyDown 捕获")
    func capturesViaKeyDown() {
        var captured: NSEvent?
        let view = makeRecorder { captured = $0; return true }

        view.mouseDown(with: mouseDown())
        view.keyDown(
            with: keyEvent(keyCode: kVK_ANSI_V, modifiers: [.control, .command], characters: "v")
        )

        #expect(captured?.keyCode == UInt16(kVK_ANSI_V))
        #expect(captured?.modifierFlags == [.control, .command])
    }

    @Test("Esc 取消录制：不回调，随后键等价恢复透传")
    func escapeCancelsRecording() {
        var captured = false
        let view = makeRecorder { _ in captured = true; return true }

        view.mouseDown(with: mouseDown())
        _ = view.performKeyEquivalent(with: keyEvent(keyCode: kVK_Escape, characters: "\u{1b}"))
        #expect(!captured)

        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: kVK_ANSI_W, modifiers: .command, characters: "w")
        )
        #expect(!handled, "取消录制后不再吞键等价")
    }

    @Test("VoiceOver 按下等价于点击：进入录制态")
    func accessibilityPressStartsRecording() {
        var captured: NSEvent?
        let view = makeRecorder { captured = $0; return true }

        #expect(view.accessibilityPerformPress())
        view.keyDown(with: keyEvent(
            keyCode: kVK_ANSI_V,
            modifiers: [.control, .command],
            characters: "v"
        ))

        #expect(captured?.keyCode == UInt16(kVK_ANSI_V))
    }

    @Test("非录制态按 Space 进入录制，随后按键被捕获")
    func spaceStartsRecording() {
        var captured: NSEvent?
        let view = makeRecorder { captured = $0; return true }

        view.keyDown(with: keyEvent(keyCode: kVK_Space, characters: " "))
        view.keyDown(with: keyEvent(
            keyCode: kVK_ANSI_V,
            modifiers: [.control, .command],
            characters: "v"
        ))

        #expect(captured?.keyCode == UInt16(kVK_ANSI_V))
    }

    @Test("注册被拒：留在录制态，可以立刻重试")
    func rejectionStaysRecording() {
        var attempts: [UInt16] = []
        var accepted = false
        let view = makeRecorder { event in
            attempts.append(event.keyCode)
            return accepted
        }

        view.mouseDown(with: mouseDown())
        view.keyDown(with: keyEvent(keyCode: kVK_ANSI_C, modifiers: [.command], characters: "c"))
        accepted = true
        view.keyDown(with: keyEvent(
            keyCode: kVK_ANSI_V,
            modifiers: [.control, .command],
            characters: "v"
        ))

        #expect(attempts == [UInt16(kVK_ANSI_C), UInt16(kVK_ANSI_V)])
    }
}
