//
//  SettingsWindowController.swift
//  SixOne
//

import AppKit
import SwiftUI

/// 设置窗口：收起面板时暂时退出 key/main 候选，避免 `orderOut` 顶替。
final class SettingsWindow: NSWindow {
    /// 仅在收起面板的同步区间内为 true。
    var refusesKeyAndMain = false

    override var canBecomeKey: Bool { !refusesKeyAndMain }
    override var canBecomeMain: Bool { !refusesKeyAndMain }
}

/// 承载 SwiftUI 设置页；关闭后保留引用。
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// 窗口尺寸；设 `contentViewController` 会改小，建完需再钉一次。
    private static let contentSize = NSSize(width: 640, height: 545)

    private let settingsWindow: SettingsWindow
    private let navigation = SettingsNavigation()
    private let settings: SettingsStore
    private let hotKeyManager: HotKeyManager
    private let loadStorageStats: () async -> HistoryStorageStats
    private let onClearHistory: () -> Void
    private var toolbarObservations: [NSKeyValueObservation] = []
    let presentation = SettingsWindowPresentation()

    init(
        settings: SettingsStore,
        hotKeyManager: HotKeyManager,
        loadStorageStats: @escaping () async -> HistoryStorageStats,
        onClearHistory: @escaping () -> Void
    ) {
        self.settings = settings
        self.hotKeyManager = hotKeyManager
        self.loadStorageStats = loadStorageStats
        self.onClearHistory = onClearHistory
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        self.settingsWindow = window
        super.init(window: window)
        window.delegate = self
        // SwiftUI 布局后才桥接出 NSToolbar；出现即锁定显示模式。
        toolbarObservations = [
            window.observe(\.toolbar, options: [.new]) { [weak self] _, _ in
                // KVO 在属性改动线程同步触发；工具栏只会被主线程布局改动。
                MainActor.assumeIsolated {
                    self?.lockToolbarToIconOnly()
                }
            }
        ]
        // LSUIElement 无 Dock 图标，最小化后难以找回：保留按钮但禁用。
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false

        window.contentViewController = NSHostingController(rootView: makeRootView())
        window.setContentSize(Self.contentSize)
        window.center()
        presentation.isWindowVisible = { [weak window] in window?.isVisible ?? false }
        presentation.bringForward.orderFront = { [weak self] in
            guard let self else { return }
            self.settingsWindow.makeKeyAndOrderFront(nil)
            self.navigation.requestSidebarFocus()
        }
    }

    private func makeRootView() -> SettingsRootView {
        SettingsRootView(
            navigation: navigation,
            settings: settings,
            hotKeyManager: hotKeyManager,
            loadStorageStats: loadStorageStats,
            onClearHistory: onClearHistory
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 显示设置窗口并激活应用。
    func showSettings() {
        // 协作式激活：只是请求，由系统按上下文裁决。
        NSApp.activate()
        settingsWindow.makeKeyAndOrderFront(nil)
        // 清掉 SwiftUI 首帧自动聚焦，避免焦点环闪在开关上。
        settingsWindow.makeFirstResponder(nil)
        prepareWindow()
        navigation.requestSidebarFocus()
        presentation.windowDidShow()
    }

    func setKeyAndMainSuspended(_ suspended: Bool) {
        settingsWindow.refusesKeyAndMain = suspended
    }

    /// 补齐 SwiftUI 宿主下管不到的工具栏显示模式。
    private func prepareWindow() {
        lockToolbarToIconOnly()
        // 工具栏可能首帧布局后才挂上，补一次锁定。
        DispatchQueue.main.async { [weak self] in
            self?.lockToolbarToIconOnly()
        }
    }

    /// 固定为仅图标并关闭显示模式自定义。
    private func lockToolbarToIconOnly() {
        guard let toolbar = settingsWindow.toolbar else { return }
        toolbar.displayMode = .iconOnly
        toolbar.allowsDisplayModeCustomization = false
    }

    func windowWillClose(_ notification: Notification) {
        navigation.reset()
    }
}

/// 读 `RuntimeLanguage`，语言变化时更新环境。
private struct SettingsRootView: View {
    let navigation: SettingsNavigation
    let settings: SettingsStore
    let hotKeyManager: HotKeyManager
    let loadStorageStats: () async -> HistoryStorageStats
    let onClearHistory: () -> Void

    var body: some View {
        let language = RuntimeLanguage.shared
        SettingsView(
            navigation: navigation,
            settings: settings,
            hotKeyManager: hotKeyManager,
            loadStorageStats: loadStorageStats,
            onClearHistory: onClearHistory
        )
        .environment(\.locale, language.locale)
        .environment(language)
    }
}
