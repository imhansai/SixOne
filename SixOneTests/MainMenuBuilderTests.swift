//
//  MainMenuBuilderTests.swift
//  SixOneTests
//  主菜单只构建一次；面板/设置模式按菜单项可见性切换。
//

import AppKit
import Testing
@testable import SixOne

@Suite("主菜单")
@MainActor
struct MainMenuBuilderTests {
    private final class Target: NSObject, AppMenuTarget {
        @objc func openSettingsFromMenu(_ sender: Any?) {}
    }

    private func makeMenu() -> BuiltMainMenu {
        MainMenuBuilder.makeMainMenu(target: Target())
    }

    private func visibleTopLevel(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.filter { !$0.isHidden }
    }

    private func visibleTitles(_ menu: NSMenu) -> [String] {
        visibleTopLevel(menu).compactMap(\.submenu?.title)
    }

    private func visibleSubmenu(_ title: String, in menu: NSMenu?) -> NSMenu? {
        menu?.items.first { !$0.isHidden && $0.submenu?.title == title }?.submenu
    }

    private func visibleNonSeparatorTitles(_ menu: NSMenu?) -> [String] {
        menu?.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title) ?? []
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

    private func visibleItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.filter { !$0.isHidden }.flatMap { item in
            guard let submenu = item.submenu else { return [item] }
            return [item] + visibleItems(in: submenu)
        }
    }

    @Test("面板模式：App / File / Edit / Item")
    func panelTopLevelOrder() {
        let built = makeMenu()
        built.apply(panelVisible: true)
        #expect(visibleTitles(built.menu) == [
            "SixOne",
            Localizer.string("File"),
            Localizer.string("Edit"),
            Localizer.string("Item"),
        ])
    }

    @Test("设置模式：App / File / Edit / Window")
    func settingsTopLevelOrder() {
        let built = makeMenu()
        built.apply(panelVisible: false)
        #expect(visibleTitles(built.menu) == [
            "SixOne",
            Localizer.string("File"),
            Localizer.string("Edit"),
            Localizer.string("Window"),
        ])
    }

    @Test("面板模式的 App 只保留设置与退出")
    func panelAppMenu() {
        let built = makeMenu()
        built.apply(panelVisible: true)
        let app = visibleSubmenu("SixOne", in: built.menu)

        #expect(visibleNonSeparatorTitles(app) == [
            Localizer.string("Settings"),
            Localizer.string("Quit SixOne"),
        ])
    }

    @Test("设置模式的 App 补齐关于、服务与隐藏")
    func settingsAppMenu() {
        let built = makeMenu()
        built.apply(panelVisible: false)
        let app = visibleSubmenu("SixOne", in: built.menu)

        #expect(visibleNonSeparatorTitles(app) == [
            Localizer.string("About SixOne"),
            Localizer.string("Settings"),
            Localizer.string("Services"),
            Localizer.string("Hide SixOne"),
            Localizer.string("Hide Others"),
            Localizer.string("Show All"),
            Localizer.string("Quit SixOne"),
        ])
        #expect(item(#selector(NSApplication.hide(_:)), in: app)?.keyEquivalent == "h")
        #expect(item(#selector(NSApplication.hideOtherApplications(_:)), in: app)?.keyEquivalent == "h")
        #expect(item(#selector(AppMenuTarget.openSettingsFromMenu(_:)), in: app)?.keyEquivalent == ",")
        #expect(item(#selector(NSApplication.terminate(_:)), in: app)?.keyEquivalent == "q")
    }

    @Test("File：面板模式有 Save，设置模式只留 Close")
    func fileMenu() {
        let built = makeMenu()
        let file = visibleSubmenu(Localizer.string("File"), in: built.menu)
        let saveTitle = PanelMenuCommandTable.entry(for: .saveEditing).title
        let close = item(#selector(NSWindow.performClose(_:)), in: file)

        built.apply(panelVisible: true)
        #expect(visibleNonSeparatorTitles(file) == [saveTitle, Localizer.string("Close Window")])
        #expect(item(#selector(ClipboardPanelController.saveEditing(_:)), in: file)?.keyEquivalent == "s")
        #expect(close?.keyEquivalent == "w")

        built.apply(panelVisible: false)
        #expect(visibleNonSeparatorTitles(file) == [Localizer.string("Close Window")])
    }

    @Test("面板 Edit：标准命令、纯文本变体与查找都在")
    func panelEditMenu() {
        let built = makeMenu()
        built.apply(panelVisible: true)
        let edit = visibleSubmenu(Localizer.string("Edit"), in: built.menu)
        let find = visibleSubmenu(Localizer.string("Find"), in: edit)

        #expect(item(#selector(NSText.cut(_:)), in: edit)?.keyEquivalent == "x")
        #expect(item(#selector(ClipboardPanelController.copy(_:)), in: edit)?.keyEquivalent == "c")
        #expect(item(#selector(ClipboardPanelController.paste(_:)), in: edit)?.keyEquivalent == "v")
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

        let search = item(#selector(ClipboardPanelController.focusSearch(_:)), in: find)
        #expect(search?.keyEquivalent == "f")
        #expect(search?.keyEquivalentModifierMask == NSEvent.ModifierFlags([.command, .option]))
    }

    @Test("设置 Edit：只留标准文本命令")
    func settingsEditMenu() {
        let built = makeMenu()
        built.apply(panelVisible: false)
        let edit = visibleSubmenu(Localizer.string("Edit"), in: built.menu)

        #expect(item(#selector(NSText.copy(_:)), in: edit)?.keyEquivalent == "c")
        #expect(item(#selector(NSText.paste(_:)), in: edit)?.keyEquivalent == "v")
        #expect(item(#selector(NSText.selectAll(_:)), in: edit)?.keyEquivalent == "a")
        #expect(item(#selector(ClipboardPanelController.copyAsPlainText(_:)), in: edit) == nil)
        #expect(visibleSubmenu(Localizer.string("Find"), in: edit) == nil)
    }

    @Test("Item 只在面板模式出现")
    func itemMenu() {
        let built = makeMenu()
        let itemMenu = visibleSubmenu(Localizer.string("Item"), in: built.menu)

        built.apply(panelVisible: true)
        #expect(visibleSubmenu(Localizer.string("Item"), in: built.menu) != nil)
        #expect(self.item(#selector(ClipboardPanelController.previewSelectedItem(_:)), in: itemMenu) != nil)
        #expect(self.item(#selector(ClipboardPanelController.shareSelectedItem(_:)), in: itemMenu) != nil)
        #expect(self.item(#selector(ClipboardPanelController.openSelectedItem(_:)), in: itemMenu)?.keyEquivalent == "o")
        #expect(self.item(#selector(ClipboardPanelController.revealSelectedItem(_:)), in: itemMenu)?.keyEquivalent == "r")
        #expect(self.item(#selector(ClipboardPanelController.clearHistory(_:)), in: itemMenu) != nil)

        built.apply(panelVisible: false)
        #expect(visibleSubmenu(Localizer.string("Item"), in: built.menu) == nil)
    }

    @Test("Window 只在设置模式出现")
    func windowMenu() {
        let built = makeMenu()
        built.apply(panelVisible: false)
        let window = visibleSubmenu(Localizer.string("Window"), in: built.menu)

        #expect(item(#selector(NSWindow.performMiniaturize(_:)), in: window)?.keyEquivalent == "m")
        #expect(item(#selector(NSWindow.performZoom(_:)), in: window) != nil)
        #expect(item(#selector(NSApplication.arrangeInFront(_:)), in: window) != nil)

        built.apply(panelVisible: true)
        #expect(visibleSubmenu(Localizer.string("Window"), in: built.menu) == nil)
    }

    @Test("每个子菜单项的根标题与子菜单标题一致")
    func submenuItemTitles() {
        let built = makeMenu()
        for item in allItems(in: built.menu) {
            guard let submenu = item.submenu else { continue }
            #expect(!item.title.isEmpty, "子菜单项没有标题：\(submenu.title)")
            #expect(item.title == submenu.title, "根标题与子菜单标题不一致：\(item.title) / \(submenu.title)")
        }
    }

    @Test("每种模式下可见项都没有重复的 key equivalent")
    func noDuplicateKeyEquivalentsPerMode() {
        let built = makeMenu()
        for panelVisible in [true, false] {
            built.apply(panelVisible: panelVisible)
            var seen: Set<String> = []
            for item in visibleItems(in: built.menu) where !item.keyEquivalent.isEmpty {
                let key = "\(item.keyEquivalentModifierMask.rawValue)-\(item.keyEquivalent)"
                #expect(seen.insert(key).inserted, "重复的快捷键：\(key)（panelVisible=\(panelVisible)）")
            }
        }
    }
}
