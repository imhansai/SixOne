//
//  PanelWindowKeyHandlingTests.swift
//  SixOneTests

import AppKit
import Carbon.HIToolbox
import Testing
@testable import SixOne

@Suite("面板窗口键盘入口")
@MainActor
struct PanelWindowKeyHandlingTests {
    private final class FakeKeyHandler: PanelKeyHandling {
        var preDispatchResult = false
        var preDispatchCount = 0
        var commandResult = false
        var commandCount = 0
        var defaultKeyDownCodes: Set<UInt16> = []
        var shouldCycleFocusWithTab = true
        var cycles: [Bool] = []
        var escapeCount = 0
        var closeCount = 0

        func handlePreDispatchKey(_ event: NSEvent) -> Bool {
            preDispatchCount += 1
            return preDispatchResult
        }

        func handleCommandKey(_ event: NSEvent) -> Bool {
            commandCount += 1
            return commandResult
        }

        func shouldUseDefaultKeyDown(for event: NSEvent) -> Bool {
            defaultKeyDownCodes.contains(event.keyCode)
        }

        func cycleFocus(backwards: Bool) {
            cycles.append(backwards)
        }

        func handleEscape() {
            escapeCount += 1
        }

        func handleCloseWindow() {
            closeCount += 1
        }
    }

    private final class FirstResponderView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    private final class FakeActionDelegate: NSObject, NSWindowDelegate {
        var moveUpCount = 0
        var insertNewlineCount = 0

        @objc func moveUp(_ sender: Any?) { moveUpCount += 1 }
        @objc func insertNewline(_ sender: Any?) { insertNewlineCount += 1 }
    }

    private func makePanel() -> (ClipboardPanel, FakeKeyHandler, FakeActionDelegate) {
        let panel = PanelWindowFactory.makePanel()
        let view = FirstResponderView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        panel.contentView = view
        let handler = FakeKeyHandler()
        let delegate = FakeActionDelegate()
        panel.keyHandler = handler
        panel.delegate = delegate
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(view)
        return (panel, handler, delegate)
    }

    private func keyEvent(
        _ keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = [],
        windowNumber: Int = 0
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    @Test("Close Window 菜单校验放行：标准 performClose: 由面板覆写成收起")
    func validatesPerformClose() {
        let (panel, _, _) = makePanel()
        defer { panel.orderOut(nil) }
        let item = NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        #expect(panel.validateUserInterfaceItem(item))
        #expect(panel.validateMenuItem(item), "fallback 的 validateMenuItem 也要放行")
    }

    @Test("sendEvent：pre-dispatch 认下就消费，不认就继续")
    func preDispatch() {
        let (panel, handler, _) = makePanel()
        handler.preDispatchResult = true
        panel.sendEvent(keyEvent(UInt16(kVK_DownArrow), characters: String(UnicodeScalar(NSDownArrowFunctionKey)!)))
        #expect(handler.preDispatchCount == 1)

        handler.preDispatchResult = false
        panel.sendEvent(keyEvent(UInt16(kVK_UpArrow), characters: String(UnicodeScalar(NSUpArrowFunctionKey)!)))
        #expect(handler.preDispatchCount == 2)
    }

    @Test("⌘F 在菜单 key equivalent 之前先交给 pre-dispatch")
    func commandFUsesPreDispatchBeforeMenu() {
        let (panel, handler, _) = makePanel()
        defer { panel.orderOut(nil) }
        handler.preDispatchResult = true

        let event = keyEvent(
            UInt16(kVK_ANSI_F),
            characters: "f",
            modifiers: [.command],
            windowNumber: panel.windowNumber
        )
        #expect(panel.performKeyEquivalent(with: event))
        #expect(handler.preDispatchCount == 1,
                "⌘F 必须先问面板路由，不能被菜单 Find… 提前吃掉")
    }

    @Test("pre-dispatch 不认时，命令键 fallback 还有一次机会")
    func commandFallback() {
        let (panel, handler, _) = makePanel()
        handler.preDispatchResult = false
        handler.commandResult = true
        panel.sendEvent(keyEvent(
            UInt16(kVK_ANSI_C),
            characters: "c",
            modifiers: [.command],
            windowNumber: panel.windowNumber
        ))
        #expect(handler.preDispatchCount == 1)
        #expect(handler.commandCount == 1)
    }

    @Test("非 keyDown 事件不经过 pre-dispatch")
    func nonKeyDownDoesNotRoute() {
        let (panel, handler, _) = makePanel()
        let mouse = NSEvent.mouseEvent(
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
        panel.sendEvent(mouse)
        #expect(handler.preDispatchCount == 0)
    }

    @Test("keyDown 交给 interpretKeyEvents：↑ → moveUp:，Return → insertNewline:")
    func keyDownStandardActions() {
        let (panel, handler, delegate) = makePanel()
        handler.preDispatchResult = false
        panel.sendEvent(keyEvent(
            UInt16(kVK_UpArrow),
            characters: String(UnicodeScalar(NSUpArrowFunctionKey)!),
            windowNumber: panel.windowNumber
        ))
        panel.sendEvent(keyEvent(
            UInt16(kVK_Return),
            characters: "\r",
            windowNumber: panel.windowNumber
        ))
        #expect(delegate.moveUpCount == 1)
        #expect(delegate.insertNewlineCount == 1)
    }

    @Test("Esc 走窗口的 cancelOperation → handler.handleEscape")
    func escape() {
        let (panel, handler, _) = makePanel()
        panel.cancelOperation(nil)
        #expect(handler.escapeCount == 1)
    }

    @Test("Tab：handler 允许时走焦点循环，不允许时交给系统")
    func tabRouting() {
        let (panel, handler, _) = makePanel()
        handler.shouldCycleFocusWithTab = true
        panel.selectNextKeyView(nil)
        panel.selectPreviousKeyView(nil)
        #expect(handler.cycles == [false, true])

        handler.shouldCycleFocusWithTab = false
        panel.selectNextKeyView(nil)
        #expect(handler.cycles == [false, true], "预览中或不允许时不该再插一脚")
    }

    @Test("⌘W / performClose 交给 handler 决定收起还是取消编辑")
    func performCloseRoutesToHandler() {
        let (panel, handler, _) = makePanel()
        panel.performClose(nil)
        #expect(handler.closeCount == 1)
    }
}
