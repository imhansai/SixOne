//
//  MainMenuBuilder.swift
//  SixOne
//
//  LSUIElement 应用的主菜单只作快捷键命令表：保留需要快捷键的命令，动作走响应链。
//

import AppKit

@objc protocol AppMenuTarget: AnyObject {
    func openSettingsFromMenu(_ sender: Any?)
}

enum MainMenuBuilder {
    static func makeMainMenu(target: AppMenuTarget) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenu(target: target))
        mainMenu.addItem(fileMenu())
        mainMenu.addItem(editMenu())
        mainMenu.addItem(itemMenu())
        return mainMenu
    }

    // MARK: - App

    private static func appMenu(target: AppMenuTarget) -> NSMenuItem {
        submenu("SixOne") { menu in
            menu.addItem(item(
                title: Localizer.string("Settings"),
                action: #selector(AppMenuTarget.openSettingsFromMenu(_:)),
                key: ",",
                target: target
            ))
            menu.addItem(.separator())
            menu.addItem(item(
                title: Localizer.string("Quit SixOne"),
                action: #selector(NSApplication.terminate(_:)),
                key: "q"
            ))
        }
    }

    // MARK: - File

    private static func fileMenu() -> NSMenuItem {
        submenu(Localizer.string("File")) { menu in
            menu.addItem(item(
                title: Localizer.string("Save"),
                action: #selector(ClipboardPanelController.saveEditing(_:)),
                key: "s"
            ))
            menu.addItem(.separator())
            menu.addItem(item(
                title: Localizer.string("Close Window"),
                action: #selector(NSWindow.performClose(_:)),
                key: "w"
            ))
        }
    }

    // MARK: - Edit

    private static func editMenu() -> NSMenuItem {
        submenu(Localizer.string("Edit")) { menu in
            menu.addItem(item(
                title: Localizer.string("Undo"),
                action: Selector(("undo:")),
                key: "z"
            ))
            menu.addItem(item(
                title: Localizer.string("Redo"),
                action: Selector(("redo:")),
                key: "z",
                modifiers: [.command, .shift]
            ))
            menu.addItem(.separator())

            menu.addItem(item(
                title: Localizer.string("Cut"),
                action: #selector(NSText.cut(_:)),
                key: "x"
            ))
            menu.addItem(item(
                title: Localizer.string("Copy"),
                action: #selector(NSText.copy(_:)),
                key: "c"
            ))
            menu.addItem(item(
                title: Localizer.string("Copy as Plain Text"),
                action: #selector(ClipboardPanelController.copyAsPlainText(_:)),
                key: "c",
                modifiers: [.command, .shift]
            ))
            menu.addItem(item(
                title: Localizer.string("Paste"),
                action: #selector(NSText.paste(_:)),
                key: "v"
            ))
            menu.addItem(item(
                title: Localizer.string("Paste as Plain Text"),
                action: #selector(ClipboardPanelController.pasteAsPlainText(_:)),
                key: "v",
                modifiers: [.command, .shift]
            ))
            menu.addItem(item(
                title: Localizer.string("Delete"),
                action: #selector(NSText.delete(_:)),
                key: "\u{7f}"
            ))
            menu.addItem(item(
                title: Localizer.string("Select All"),
                action: #selector(NSText.selectAll(_:)),
                key: "a"
            ))
            menu.addItem(.separator())
            menu.addItem(findMenu())
        }
    }

    /// 查找子菜单：首项面板搜索，其余交给 NSTextFinder。
    private static func findMenu() -> NSMenuItem {
        submenu(Localizer.string("Find")) { menu in
            menu.addItem(item(
                title: Localizer.string("Search Clipboard"),
                action: #selector(ClipboardPanelController.focusSearch(_:)),
                key: "f",
                modifiers: [.command, .option]
            ))
            menu.addItem(.separator())

            menu.addItem(finderItem(
                title: Localizer.string("Find…"),
                key: "f",
                modifiers: [.command],
                action: .showFindInterface
            ))
            menu.addItem(finderItem(
                title: Localizer.string("Find Next"),
                key: "g",
                modifiers: [.command],
                action: .nextMatch
            ))
            menu.addItem(finderItem(
                title: Localizer.string("Find Previous"),
                key: "g",
                modifiers: [.command, .shift],
                action: .previousMatch
            ))
            menu.addItem(finderItem(
                title: Localizer.string("Use Selection for Find"),
                key: "e",
                modifiers: [.command],
                action: .setSearchString
            ))
            menu.addItem(.separator())
            menu.addItem(finderItem(
                title: Localizer.string("Replace…"),
                key: "r",
                modifiers: [.command, .option],
                action: .showReplaceInterface
            ))
            menu.addItem(finderItem(
                title: Localizer.string("Replace All"),
                key: "a",
                modifiers: [.command, .option],
                action: .replaceAll
            ))
        }
    }

    /// 用 tag 携带 `NSTextFinder.Action`，NSTextView 按 tag 转发。
    private static func finderItem(
        title: String,
        key: String,
        modifiers: NSEvent.ModifierFlags,
        action: NSTextFinder.Action
    ) -> NSMenuItem {
        let item = item(
            title: title,
            action: #selector(NSResponder.performTextFinderAction(_:)),
            key: key,
            modifiers: modifiers
        )
        item.tag = action.rawValue
        return item
    }

    // MARK: - Item

    private static func itemMenu() -> NSMenuItem {
        submenu(Localizer.string("Item")) { menu in
            menu.addItem(item(
                title: Localizer.string("Preview"),
                action: #selector(ClipboardPanelController.previewSelectedItem(_:)),
                key: ""
            ))
            menu.addItem(.separator())
            menu.addItem(item(
                title: Localizer.string("Share…"),
                action: #selector(ClipboardPanelController.shareSelectedItem(_:)),
                key: ""
            ))
            menu.addItem(item(
                title: Localizer.string("Open"),
                action: #selector(ClipboardPanelController.openSelectedItem(_:)),
                key: "o"
            ))
            menu.addItem(item(
                title: Localizer.string("Reveal in Finder"),
                action: #selector(ClipboardPanelController.revealSelectedItem(_:)),
                key: "r",
                modifiers: [.command, .shift]
            ))
            menu.addItem(.separator())
            menu.addItem(item(
                title: Localizer.string("Clear History…"),
                action: #selector(ClipboardPanelController.clearHistory(_:)),
                key: ""
            ))
        }
    }

    // MARK: - 工具

    /// 顶层菜单项 + 子菜单；根项标题由子菜单标题显示。
    private static func submenu(_ title: String, build: (NSMenu) -> Void) -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: title)
        root.submenu = menu
        build(menu)
        return root
    }

    /// 空 key equivalent 用空 modifier mask，避免 AppKit 补上默认 ⌘。
    private static func item(
        title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = target
        return item
    }
}
