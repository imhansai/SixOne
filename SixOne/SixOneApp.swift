//
//  SixOneApp.swift
//  SixOne

import AppKit

/// 应用入口：不依赖 SwiftUI Scene，完全由 AppKit 驱动（菜单栏状态项 + 自绘面板）。
@main
enum SixOneApp {
    static func main() {
        // 创建 NSApplication 前恢复运行时语言，让 Bundle 与系统文案按所选语言解析。
        RuntimeLanguage.shared.restoreFromDefaults()
        RuntimeLanguage.shared.applyToDefaults()
        // 关掉 AppKit 的 AutoFill 启发式，避免唤出面板时闪候选浮窗；键未公开，可能失效。
        UserDefaults.standard.register(defaults: ["NSAutoFillHeuristicsEnabled": false])
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
