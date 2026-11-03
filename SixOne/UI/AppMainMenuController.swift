//
//  AppMainMenuController.swift
//  SixOne
//
//  主菜单只安装一次；面板/设置模式只切换菜单项可见性，不替换 NSMenu。
//

import AppKit

typealias AppMenuInstaller = (
    _ mainMenu: NSMenu,
    _ servicesMenu: NSMenu?,
    _ windowsMenu: NSMenu?
) -> Void

@MainActor
final class AppMainMenuController {
    enum Mode: Equatable {
        case panel
        case settings
    }

    private let built: BuiltMainMenu
    private let installMenus: AppMenuInstaller
    private var isPanelVisible = false
    private var isSettingsVisible = false
    private var installedMode: Mode?

    init(
        target: AppMenuTarget,
        installMenus: @escaping AppMenuInstaller = { mainMenu, servicesMenu, windowsMenu in
            NSApp.mainMenu = mainMenu
            NSApp.servicesMenu = servicesMenu
            NSApp.windowsMenu = windowsMenu
        }
    ) {
        built = MainMenuBuilder.makeMainMenu(target: target)
        self.installMenus = installMenus
    }

    var currentMode: Mode {
        isPanelVisible ? .panel : (isSettingsVisible ? .settings : .panel)
    }

    func install() {
        // AppKit 的 Window 菜单会自行维护窗口列表与标准项；只注册一次，不重建。
        installMenus(built.menu, built.servicesMenu, built.windowsMenu)
        applyMode(force: true)
    }

    func setPanelVisible(_ visible: Bool) {
        guard isPanelVisible != visible else { return }
        isPanelVisible = visible
        applyMode()
    }

    func setSettingsVisible(_ visible: Bool) {
        guard isSettingsVisible != visible else { return }
        isSettingsVisible = visible
        applyMode()
    }

    private func applyMode(force: Bool = false) {
        let mode = currentMode
        guard force || mode != installedMode else { return }
        installedMode = mode
        built.apply(panelVisible: mode == .panel)
    }
}
