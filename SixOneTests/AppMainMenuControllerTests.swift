//
//  AppMainMenuControllerTests.swift
//  SixOneTests
//  主菜单只安装一次；面板/设置模式只切换菜单项可见性。
//

import AppKit
import Testing
@testable import SixOne

@Suite("主菜单切换")
@MainActor
struct AppMainMenuControllerTests {
    private final class Target: NSObject, AppMenuTarget {
        @objc func openSettingsFromMenu(_ sender: Any?) {}
    }

    private final class Installer {
        var mainMenus: [NSMenu] = []
        var servicesMenus: [NSMenu?] = []
        var windowsMenus: [NSMenu?] = []

        func install(_ mainMenu: NSMenu, _ servicesMenu: NSMenu?, _ windowsMenu: NSMenu?) {
            mainMenus.append(mainMenu)
            servicesMenus.append(servicesMenu)
            windowsMenus.append(windowsMenu)
        }
    }

    private func visibleTitles(_ menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isHidden }.compactMap(\.submenu?.title)
    }

    @Test("菜单只安装一次，模式切换不重建")
    func installsOnce() {
        let installer = Installer()
        let target = Target()
        let controller = AppMainMenuController(target: target, installMenus: installer.install)

        controller.install()
        controller.setSettingsVisible(true)
        controller.setPanelVisible(true)
        controller.setPanelVisible(false)
        controller.setSettingsVisible(false)

        #expect(installer.mainMenus.count == 1)
        #expect(installer.servicesMenus.count == 1)
        #expect(installer.windowsMenus.count == 1)
    }

    @Test("模式切换更新菜单项可见性")
    func visibilityFollowsMode() {
        let installer = Installer()
        let target = Target()
        let controller = AppMainMenuController(target: target, installMenus: installer.install)

        controller.install()
        let menu = installer.mainMenus[0]
        #expect(visibleTitles(menu) == [
            "SixOne",
            Localizer.string("File"),
            Localizer.string("Edit"),
            Localizer.string("Item"),
        ])

        controller.setSettingsVisible(true)
        #expect(visibleTitles(menu) == [
            "SixOne",
            Localizer.string("File"),
            Localizer.string("Edit"),
            Localizer.string("Window"),
        ])

        controller.setPanelVisible(true)
        #expect(visibleTitles(menu) == [
            "SixOne",
            Localizer.string("File"),
            Localizer.string("Edit"),
            Localizer.string("Item"),
        ])

        controller.setPanelVisible(false)
        #expect(visibleTitles(menu) == [
            "SixOne",
            Localizer.string("File"),
            Localizer.string("Edit"),
            Localizer.string("Window"),
        ])
    }

    @Test("面板可见时优先用面板模式")
    func panelWinsWhileVisible() {
        let target = Target()
        let controller = AppMainMenuController(target: target, installMenus: { _, _, _ in })

        controller.setSettingsVisible(true)
        #expect(controller.currentMode == .settings)

        controller.setPanelVisible(true)
        #expect(controller.currentMode == .panel)

        controller.setPanelVisible(false)
        #expect(controller.currentMode == .settings)
    }
}
