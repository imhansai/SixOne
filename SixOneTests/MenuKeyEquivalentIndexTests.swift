//
//  MenuKeyEquivalentIndexTests.swift
//  SixOneTests
//  命令键 fallback 只认主菜单：菜单里有的能查到，没有的查不到。

import AppKit
import Carbon.HIToolbox
import Testing
@testable import SixOne

@Suite("菜单命令键索引")
@MainActor
struct MenuKeyEquivalentIndexTests {
    private final class Target: NSObject, AppMenuTarget {
        @objc func openSettingsFromMenu(_ sender: Any?) {}
    }

    private func makeIndex() -> MenuKeyEquivalentIndex {
        MenuKeyEquivalentIndex(menu: MainMenuBuilder.makeMainMenu(target: Target()))
    }

    private func event(
        _ character: String,
        _ modifiers: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_A)
        )!
    }

    @Test("⌘C / ⇧⌘C / ⌘S / ⌘W / ⌘, / ⌘⌫ 都能从菜单查到")
    func basicCommandKeys() {
        let index = makeIndex()

        #expect(index.command(for: event("c", [.command]))?.action == #selector(NSText.copy(_:)))
        #expect(index.command(for: event("c", [.command, .shift]))?.action
            == #selector(ClipboardPanelController.copyAsPlainText(_:)))
        #expect(index.command(for: event("w", [.command]))?.action
            == #selector(NSWindow.performClose(_:)))
        #expect(index.command(for: event(",", [.command]))?.action
            == Selector(("openSettingsFromMenu:")))
        #expect(index.command(for: event("\u{7f}", [.command]))?.action
            == #selector(NSText.delete(_:)))
        #expect(index.command(for: event("s", [.command]))?.action
            == #selector(ClipboardPanelController.saveEditing(_:)))
    }

    @Test("查找命令保留菜单项的 tag")
    func finderCommandsKeepTag() {
        let index = makeIndex()

        let find = index.command(for: event("f", [.command]))
        #expect(find?.action == #selector(NSResponder.performTextFinderAction(_:)))
        #expect(find?.tag == NSTextFinder.Action.showFindInterface.rawValue)

        let previous = index.command(for: event("g", [.command, .shift]))
        #expect(previous?.tag == NSTextFinder.Action.previousMatch.rawValue)

        let search = index.command(for: event("f", [.command, .option]))
        #expect(search?.action == #selector(ClipboardPanelController.focusSearch(_:)))
    }

    @Test("Item 菜单的 ⌘O / ⇧⌘R 也在索引里")
    func itemCommands() {
        let index = makeIndex()

        #expect(index.command(for: event("o", [.command]))?.action
            == #selector(ClipboardPanelController.openSelectedItem(_:)))
        #expect(index.command(for: event("r", [.command, .shift]))?.action
            == #selector(ClipboardPanelController.revealSelectedItem(_:)))
    }

    @Test("没有 ⌘ 或菜单里没有的组合不接管")
    func ignoresUnmappedKeys() {
        let index = makeIndex()

        #expect(index.command(for: event("c", [])) == nil)
        #expect(index.command(for: event("b", [.command])) == nil)
    }

    @Test("命中后 perform 会用菜单项的 target/action")
    func performsMenuItemAction() {
        final class Target: NSObject {
            var called = false
            @objc func hit(_ sender: Any?) { called = true }
        }
        let target = Target()
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Hit",
            action: #selector(Target.hit(_:)),
            keyEquivalent: "k"
        )
        item.keyEquivalentModifierMask = [.command]
        item.target = target
        menu.addItem(item)

        let index = MenuKeyEquivalentIndex(menu: menu)
        let command = index.command(for: event("k", [.command]))
        #expect(command?.performValidated() == true)
        #expect(target.called)
    }

    @Test("校验返回 false 时不执行 action")
    func validationRejectsCommand() {
        final class Target: NSObject, NSMenuItemValidation {
            var called = false
            @objc func hit(_ sender: Any?) { called = true }
            func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { false }
        }
        let target = Target()
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Rejected",
            action: #selector(Target.hit(_:)),
            keyEquivalent: "k"
        )
        item.keyEquivalentModifierMask = [.command]
        item.target = target
        menu.addItem(item)

        let index = MenuKeyEquivalentIndex(menu: menu)
        #expect(index.command(for: event("k", [.command]))?.performValidated() == false)
        #expect(!target.called)
    }

    @Test("空菜单得到空索引")
    func emptyMenu() {
        let index = MenuKeyEquivalentIndex(menu: nil)
        #expect(index.command(for: event("c", [.command])) == nil)
    }
}
