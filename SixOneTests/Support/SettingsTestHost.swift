//
//  SettingsTestHost.swift
//  SixOneTests
//
//  设置窗口的测试宿主：几何与控制器一致，供窗口级契约测试共用。
//

import AppKit
import SwiftUI
@testable import SixOne

@MainActor
enum SettingsTestHost {
    static let contentSize = NSSize(width: 640, height: 545)

    static func make() -> (navigation: SettingsNavigation, window: NSWindow) {
        let navigation = SettingsNavigation()
        let view = SettingsView(
            navigation: navigation,
            settings: SettingsStore(storage: InMemorySettingsStorage()),
            hotKeyManager: HotKeyManager(onTrigger: {}, storage: InMemorySettingsStorage()),
            loadStorageStats: { HistoryStorageStats(itemCount: 0, byteCount: 0) },
            onClearHistory: {}
        )
        .environment(RuntimeLanguage.shared)
        .environment(\.locale, RuntimeLanguage.shared.locale)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        // 赋值 contentViewController 会按内容改小窗口，之后要再钉一次。
        window.setContentSize(contentSize)
        window.contentView?.layoutSubtreeIfNeeded()
        return (navigation, window)
    }
}
