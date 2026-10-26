//
//  ShortcutConflictCheckerTests.swift
//  SixOneTests

import AppKit
import Carbon.HIToolbox
import Testing
@testable import SixOne

@Suite("快捷键菜单冲突预检")
@MainActor
struct ShortcutConflictCheckerTests {
    private func keyEvent(
        _ keyCode: Int,
        modifiers: NSEvent.ModifierFlags,
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

    private func menuWithPlainCopy() -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Copy as Plain Text",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "c"
        )
        item.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(item)
        return menu
    }

    @Test("命中主菜单 key equivalent：判为冲突")
    func menuConflict() {
        let checker = ShortcutConflictChecker(menu: menuWithPlainCopy())
        let event = keyEvent(kVK_ANSI_C, modifiers: [.command, .shift], characters: "C")

        #expect(checker.conflictsWithMenu(event))
    }

    @Test("主菜单没有的组合：放行")
    func noConflict() {
        let checker = ShortcutConflictChecker(menu: menuWithPlainCopy())
        let event = keyEvent(kVK_ANSI_Y, modifiers: [.command, .option], characters: "y")

        #expect(!checker.conflictsWithMenu(event))
    }

    @Test("没有主菜单：一律放行")
    func noMenu() {
        let checker = ShortcutConflictChecker(menu: nil)
        let event = keyEvent(kVK_ANSI_C, modifiers: [.command, .shift], characters: "C")

        #expect(!checker.conflictsWithMenu(event))
    }
}
