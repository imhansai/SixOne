//
//  MainMenuBuilder.swift
//  SixOne
//
//  主菜单只构建一次：面板模式隐藏应用级命令，设置模式隐藏面板专用命令。
//

import AppKit

@objc protocol AppMenuTarget: AnyObject {
    func openSettingsFromMenu(_ sender: Any?)
}

/// 常驻主菜单，以及按模式收起的菜单项。
struct BuiltMainMenu {
    let menu: NSMenu
    let servicesMenu: NSMenu
    let windowsMenu: NSMenu
    /// 面板可见时隐藏：应用级命令、Window 菜单与设置模式专用的 Edit。
    let hiddenWhilePanelVisible: [NSMenuItem]
    /// 设置窗口可见时隐藏：面板专用菜单与 File > Save。
    let hiddenWhileSettingsVisible: [NSMenuItem]

    func apply(panelVisible: Bool) {
        for item in hiddenWhilePanelVisible {
            item.isHidden = panelVisible
        }
        for item in hiddenWhileSettingsVisible {
            item.isHidden = !panelVisible
        }
    }
}

enum MainMenuBuilder {
    static func makeMainMenu(target: AppMenuTarget) -> BuiltMainMenu {
        let services = submenuItem(Localizer.string("Services"))
        let servicesSeparator = NSMenuItem.separator()

        let about = item(
            title: Localizer.string("About SixOne"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            key: ""
        )
        let aboutSeparator = NSMenuItem.separator()
        let settings = item(
            title: Localizer.string("Settings"),
            action: #selector(AppMenuTarget.openSettingsFromMenu(_:)),
            key: ",",
            target: target
        )
        let settingsSeparator = NSMenuItem.separator()
        let hide = item(
            title: Localizer.string("Hide SixOne"),
            action: #selector(NSApplication.hide(_:)),
            key: "h"
        )
        let hideOthers = item(
            title: Localizer.string("Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            key: "h",
            modifiers: [.command, .option]
        )
        let showAll = item(
            title: Localizer.string("Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            key: ""
        )
        let quitSeparator = NSMenuItem.separator()
        let quit = item(
            title: Localizer.string("Quit SixOne"),
            action: #selector(NSApplication.terminate(_:)),
            key: "q"
        )

        let appMenu = NSMenu(title: "SixOne")
        appMenu.addItem(about)
        appMenu.addItem(aboutSeparator)
        appMenu.addItem(settings)
        appMenu.addItem(settingsSeparator)
        appMenu.addItem(services.item)
        appMenu.addItem(servicesSeparator)
        appMenu.addItem(hide)
        appMenu.addItem(hideOthers)
        appMenu.addItem(showAll)
        appMenu.addItem(quitSeparator)
        appMenu.addItem(quit)
        let appRoot = menuItem("SixOne", appMenu)

        let fileSeparator = NSMenuItem.separator()
        let save = commandItem(.saveEditing)
        let close = item(
            title: Localizer.string("Close Window"),
            action: #selector(NSWindow.performClose(_:)),
            key: "w"
        )
        let fileMenu = NSMenu(title: Localizer.string("File"))
        fileMenu.addItem(save)
        fileMenu.addItem(fileSeparator)
        fileMenu.addItem(close)
        let fileRoot = menuItem(Localizer.string("File"), fileMenu)

        let panelEditRoot = panelEditMenu()
        let settingsEditRoot = settingsEditMenu()
        let itemRoot = itemMenu()
        let window = windowMenu()

        let mainMenu = NSMenu()
        mainMenu.addItem(appRoot)
        mainMenu.addItem(fileRoot)
        mainMenu.addItem(panelEditRoot)
        mainMenu.addItem(settingsEditRoot)
        mainMenu.addItem(itemRoot)
        mainMenu.addItem(window.item)

        return BuiltMainMenu(
            menu: mainMenu,
            servicesMenu: services.menu,
            windowsMenu: window.menu,
            hiddenWhilePanelVisible: [
                about, aboutSeparator, services.item, servicesSeparator,
                hide, hideOthers, showAll, quitSeparator,
                settingsEditRoot, window.item,
            ],
            hiddenWhileSettingsVisible: [
                panelEditRoot, itemRoot, save, fileSeparator,
            ]
        )
    }

    // MARK: - 面板模式

    private static func panelEditMenu() -> NSMenuItem {
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
            menu.addItem(commandItem(.copy))
            menu.addItem(commandItem(.copyAsPlainText))
            menu.addItem(commandItem(.paste))
            menu.addItem(commandItem(.pasteAsPlainText))
            menu.addItem(commandItem(.delete))
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
            menu.addItem(commandItem(.focusSearch))
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

    private static func itemMenu() -> NSMenuItem {
        submenu(Localizer.string("Item")) { menu in
            menu.addItem(commandItem(.preview))
            menu.addItem(.separator())
            menu.addItem(commandItem(.share))
            menu.addItem(commandItem(.open))
            menu.addItem(commandItem(.reveal))
            menu.addItem(.separator())
            menu.addItem(commandItem(.clearHistory))
        }
    }

    // MARK: - 设置模式

    private static func settingsEditMenu() -> NSMenuItem {
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
                title: Localizer.string("Paste"),
                action: #selector(NSText.paste(_:)),
                key: "v"
            ))
            menu.addItem(item(
                title: Localizer.string("Select All"),
                action: #selector(NSText.selectAll(_:)),
                key: "a"
            ))
        }
    }

    private static func windowMenu() -> (item: NSMenuItem, menu: NSMenu) {
        submenuItem(Localizer.string("Window")) { menu in
            menu.addItem(item(
                title: Localizer.string("Minimize"),
                action: #selector(NSWindow.performMiniaturize(_:)),
                key: "m"
            ))
            menu.addItem(item(
                title: Localizer.string("Zoom"),
                action: #selector(NSWindow.performZoom(_:)),
                key: ""
            ))
            menu.addItem(.separator())
            menu.addItem(item(
                title: Localizer.string("Bring All to Front"),
                action: #selector(NSApplication.arrangeInFront(_:)),
                key: ""
            ))
        }
    }

    // MARK: - 工具

    /// 命令项元数据来自 `PanelMenuCommandTable`；菜单树本身仍显式搭建。
    private static func commandItem(_ command: PanelMenuCommand) -> NSMenuItem {
        let entry = PanelMenuCommandTable.entry(for: command)
        return item(
            title: entry.title,
            action: entry.selector,
            key: entry.key,
            modifiers: entry.modifiers
        )
    }

    /// 根项与子菜单共用标题；嵌套项没标题会显示成 NSMenuItem。
    private static func submenu(_ title: String, build: (NSMenu) -> Void = { _ in }) -> NSMenuItem {
        submenuItem(title, build: build).item
    }

    private static func submenuItem(
        _ title: String,
        build: (NSMenu) -> Void = { _ in }
    ) -> (item: NSMenuItem, menu: NSMenu) {
        let menu = NSMenu(title: title)
        build(menu)
        return (menuItem(title, menu), menu)
    }

    private static func menuItem(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let root = NSMenuItem()
        root.title = title
        root.submenu = menu
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
