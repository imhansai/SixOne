//
//  AppDelegate.swift
//  SixOne

import AppKit
import SwiftData
import os

final class AppDelegate: NSObject, NSApplicationDelegate, AppMenuTarget {
    private var statusBarController: StatusBarController?
    private var clipboardManager: ClipboardManager?
    private var hotKeyManager: HotKeyManager?
    private var panelController: ClipboardPanelController?
    private var settingsWindowController: SettingsWindowController?
    private var settingsStore: SettingsStore?

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
        NSApp.mainMenu = MainMenuBuilder.makeMainMenu(target: self)
        guard !Self.isRunningUnitTests else { return }

        let composition = AppComposition(modelContainer: modelContainer)
        let settingsStore = composition.settings
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
        // 收起面板时摘掉设置窗口的 key/main 候选资格。
        panelController.setSettingsKeyAndMainSuspended = { [weak self] suspended in
            self?.settingsWindowController?.setKeyAndMainSuspended(suspended)
        }
        statusBar.updateOpenClipboardShortcut()

        self.statusBarController = statusBar
        self.clipboardManager = composition.panel.manager
        self.hotKeyManager = hotKeyManager
        self.panelController = panelController
        self.settingsStore = settingsStore
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    /// 退出前拦一道未提交的预览编辑；编辑结束后再按一次 ⌘Q 才退出。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard panelController?.handleQuitAttempt() == true else { return .terminateNow }
        return .terminateCancel
    }

    @objc func openSettings() {
        // 不恢复焦点到唤出前的应用，避免与激活设置窗口产生竞态。
        panelController?.hide(restoresPreviousApplication: false)
        guard let settingsStore, let hotKeyManager else { return }
        let container = modelContainer
        let controller = settingsWindowController ?? SettingsWindowController(
            settings: settingsStore,
            hotKeyManager: hotKeyManager,
            loadStorageStats: {
                await HistoryStorageStatsReader.read(container: container)
            },
            onClearHistory: { [weak self] in
                self?.clipboardManager?.clearAll()
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
