//
//  AppDelegate.swift
//  SixOne

import AppKit
import SwiftData
import os

final class AppDelegate: NSObject, NSApplicationDelegate, AppMenuTarget {
    private var statusBarController: StatusBarController?
    /// 组合根；数据层、面板与快捷键都由它持有。
    private var composition: AppComposition?
    private var settingsWindowController: SettingsWindowController?
    private var appMenu: AppMainMenuController?
    private lazy var activationPolicy = AppActivationPolicy(isEnabled: !Self.isRunningUnitTests)
    /// 等待应用退出激活后再显示设置窗口。
    private var deactivationObserver: NSObjectProtocol?

    /// 是否单测宿主；测试宿主与运行中的 SixOne 同容器、同快捷键。
    static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["SIXONE_UNIT_TESTS"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// 测试宿主里只保留「进程活着承载测试包」：不建真实库、不起监控/快捷键/状态栏。
    private lazy var modelContainer: ModelContainer =
        AppModelContainer.make(isStoredInMemoryOnly: Self.isRunningUnitTests)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = AppMainMenuController(target: self)
        self.appMenu = appMenu
        appMenu.install()
        guard !Self.isRunningUnitTests else { return }

        let composition = AppComposition(modelContainer: modelContainer)
        self.composition = composition
        let panelController = composition.controller
        let hotKeyManager = composition.hotKey

        let statusBar = StatusBarController(
            onToggleClipboard: { [weak panelController] in
                panelController?.toggle(anchor: .statusItem)
            },
            onOpenClipboard: { [weak panelController] in
                panelController?.show(anchor: .statusItem)
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            onOpenAbout: { [weak self] in
                self?.openAbout()
            },
            hotKeyManager: hotKeyManager
        )
        panelController.positionProvider = { [weak statusBar] in
            statusBar?.statusButtonScreenRect
        }
        panelController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        // 面板可见时主菜单退回快捷键命令表，避免应用级快捷键截走面板按键。
        panelController.onPanelVisibilityChange = { [weak self] visible in
            self?.appMenu?.setPanelVisible(visible)
        }
        // 收起面板时摘掉设置窗口的 key/main 候选资格。
        panelController.setSettingsKeyAndMainSuspended = { [weak self] suspended in
            self?.settingsWindowController?.setKeyAndMainSuspended(suspended)
        }
        statusBar.updateOpenClipboardShortcut()

        self.statusBarController = statusBar
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    /// Dock 图标只在设置窗口打开期间存在；从 Dock / Finder 重开时落到设置。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !Self.isRunningUnitTests else { return true }
        if !flag {
            openSettings()
        }
        return true
    }

    /// 退出前拦一道未提交的预览编辑；编辑结束后再按一次 ⌘Q 才退出。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard composition?.controller.handleQuitAttempt() == true else { return .terminateNow }
        return .terminateCancel
    }

    @objc func openSettings() {
        guard deactivationObserver == nil else { return }
        let wasPanelVisible = composition?.controller.isPanelVisible ?? false
        // 设置窗口已显示时应用已是常规身份，无需交还激活。
        let settingsVisible = settingsWindowController?.window?.isVisible == true
        // 激活态下切常规身份会让系统菜单栏留在上一个应用手里；
        // 先收起面板交还激活，等应用真正退出前台后再显示设置窗口。
        let handedOff = composition?.controller.hide(
            restoresPreviousApplication: !settingsVisible
        ) ?? false
        guard wasPanelVisible, !settingsVisible, handedOff, NSApp.isActive else {
            presentSettings()
            return
        }
        // 交还激活是异步的，didResignActive 才是完成信号。
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finishDeactivationWait()
            }
        }
    }

    private func finishDeactivationWait() {
        if let deactivationObserver {
            NotificationCenter.default.removeObserver(deactivationObserver)
        }
        deactivationObserver = nil
        presentSettings()
    }

    private func presentSettings() {
        guard let composition else { return }
        let container = modelContainer
        let controller = settingsWindowController ?? SettingsWindowController(
            settings: composition.settings,
            hotKeyManager: composition.hotKey,
            activationPolicy: activationPolicy,
            onVisibilityChange: { [weak self] visible in
                self?.appMenu?.setSettingsVisible(visible)
            },
            loadStorageStats: {
                await HistoryStorageStatsReader.read(container: container)
            },
            onClearHistory: { [weak self] in
                self?.composition?.panel.manager.clearAll()
            }
        )
        settingsWindowController = controller
        controller.showSettings()
    }

    // MARK: - AppMenuTarget

    @objc func openSettingsFromMenu(_ sender: Any?) {
        openSettings()
    }

    private func openAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

/// 应用重启：派生子进程后终止自己，让新实例读入新语言。
enum AppRelauncher {
    private static let logger = AppLog.logger("Relaunch")

    /// 派生子进程后终止自己；失败要留日志。
    static func relaunch() {
        // 马上要终止进程，显式冲一次偏好写入。
        UserDefaults.standard.synchronize()
        guard let executableURL = Bundle.main.executableURL else {
            logger.error("重启失败：取不到自身的可执行文件路径")
            return
        }
        let process = Process()
        process.executableURL = executableURL
        do {
            try process.run()
        } catch {
            logger.error("重启失败：无法派生新进程 \(error.localizedDescription, privacy: .public)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }
}
