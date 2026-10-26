//
//  MainMenuBuilderTests.swift
//  SixOneTests
//  主菜单结构：LSUIElement 下不显示，仅作快捷键命令表；key equivalent 不能写歪。

import AppKit
import Testing
@testable import SixOne

@Suite("主菜单")
@MainActor
struct MainMenuBuilderTests {
    private final class Target: NSObject, AppMenuTarget {
        @objc func openSettingsFromMenu(_ sender: Any?) {}
    }

    private func makeMenu() -> NSMenu {
        MainMenuBuilder.makeMainMenu(target: Target())
    }

    private func submenu(_ title: String, in menu: NSMenu?) -> NSMenu? {
        menu?.items.compactMap(\.submenu).first { $0.title == title }
    }

    private func item(_ action: Selector, in menu: NSMenu?) -> NSMenuItem? {
        menu?.items.first { $0.action == action && !$0.isSeparatorItem }
    }

    private func allItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in
            guard let submenu = item.submenu else { return [item] }
            return [item] + allItems(in: submenu)
        }
    }

    @Test("顶层菜单顺序：App / File / Edit / Item")
    func topLevelOrder() {
        let menu = makeMenu()
        #expect(menu.items.compactMap(\.submenu).map(\.title) == [
            "SixOne",
            Localizer.string("File"),
            Localizer.string("Edit"),
            Localizer.string("Item"),
        ])
    }

    @Test("App：只保留有快捷键的设置与退出（主菜单不显示）")
    func appMenu() {
        let menu = makeMenu()
        let app = submenu("SixOne", in: menu)

        #expect(item(#selector(AppMenuTarget.openSettingsFromMenu(_:)), in: app)?.keyEquivalent == ",")
        #expect(item(#selector(NSApplication.terminate(_:)), in: app)?.keyEquivalent == "q")
    }

    @Test("Edit：标准命令与纯文本变体都在")
    func editMenu() {
        let menu = makeMenu()
        let edit = submenu(Localizer.string("Edit"), in: menu)

        #expect(item(#selector(NSText.copy(_:)), in: edit)?.keyEquivalent == "c")
        #expect(item(#selector(NSText.paste(_:)), in: edit)?.keyEquivalent == "v")
        #expect(item(#selector(NSText.selectAll(_:)), in: edit)?.keyEquivalent == "a")

        let plainCopy = item(#selector(ClipboardPanelController.copyAsPlainText(_:)), in: edit)
        #expect(plainCopy?.keyEquivalent == "c")
        #expect(plainCopy?.keyEquivalentModifierMask == NSEvent.ModifierFlags([.command, .shift]))

        let plainPaste = item(#selector(ClipboardPanelController.pasteAsPlainText(_:)), in: edit)
        #expect(plainPaste?.keyEquivalent == "v")
        #expect(plainPaste?.keyEquivalentModifierMask == NSEvent.ModifierFlags([.command, .shift]))

        let delete = item(#selector(NSText.delete(_:)), in: edit)
        #expect(delete?.keyEquivalent == "\u{7f}")
        #expect(delete?.keyEquivalentModifierMask == NSEvent.ModifierFlags([.command]), "删除用 ⌘⌫")
    }

    @Test("File：Save 是 ⌘S，Close Window 仍是标准 performClose:，由面板覆写成收起")
    func fileMenu() {
        let menu = makeMenu()
        let file = submenu(Localizer.string("File"), in: menu)
        let save = item(#selector(ClipboardPanelController.saveEditing(_:)), in: file)
        #expect(save?.keyEquivalent == "s")
        #expect(save?.keyEquivalentModifierMask == NSEvent.ModifierFlags([.command]))

        let close = item(#selector(NSWindow.performClose(_:)), in: file)
        #expect(close?.keyEquivalent == "w")
        #expect(close?.keyEquivalentModifierMask == NSEvent.ModifierFlags([.command]))
    }

    @Test("Find：Search Clipboard 用 ⌥⌘F，Replace 让位给 ⌥⌘R")
    func findMenu() {
        let menu = makeMenu()
        let edit = submenu(Localizer.string("Edit"), in: menu)
        let find = submenu(Localizer.string("Find"), in: edit)

        let search = item(#selector(ClipboardPanelController.focusSearch(_:)), in: find)
        #expect(search?.keyEquivalent == "f")
        #expect(search?.keyEquivalentModifierMask == NSEvent.ModifierFlags([.command, .option]))

        let findItem = find?.items.first { $0.action == #selector(NSResponder.performTextFinderAction(_:)) }
        #expect(findItem?.keyEquivalent == "f")
        #expect(findItem?.keyEquivalentModifierMask == NSEvent.ModifierFlags([.command]))

        let replace = find?.items.first {
            $0.action == #selector(NSResponder.performTextFinderAction(_:))
                && $0.tag == NSTextFinder.Action.showReplaceInterface.rawValue
        }
        #expect(replace?.keyEquivalent == "r")
        #expect(replace?.keyEquivalentModifierMask == NSEvent.ModifierFlags([.command, .option]))
    }

    @Test("Item：预览 / 分享 / 打开 / 揭示 / 清空历史")
    func itemMenu() {
        let menu = makeMenu()
        let itemMenu = submenu(Localizer.string("Item"), in: menu)

        #expect(self.item(#selector(ClipboardPanelController.previewSelectedItem(_:)), in: itemMenu) != nil)
        #expect(self.item(#selector(ClipboardPanelController.shareSelectedItem(_:)), in: itemMenu) != nil)
        #expect(self.item(#selector(ClipboardPanelController.openSelectedItem(_:)), in: itemMenu)?.keyEquivalent == "o")
        #expect(self.item(#selector(ClipboardPanelController.revealSelectedItem(_:)), in: itemMenu)?.keyEquivalent == "r")
        #expect(self.item(#selector(ClipboardPanelController.clearHistory(_:)), in: itemMenu) != nil)
    }

    @Test("整棵菜单里不出现重复的 key equivalent")
    func noDuplicateKeyEquivalents() {
        let menu = makeMenu()
        var seen: Set<String> = []
        for item in allItems(in: menu) where !item.keyEquivalent.isEmpty {
            let key = "\(item.keyEquivalentModifierMask.rawValue)-\(item.keyEquivalent)"
            #expect(seen.insert(key).inserted, "重复的快捷键：\(key)")
        }
    }
}
