//
//  AppComposition.swift
//  SixOne
//
//  组合根：数据层、面板与全局快捷键的装配与接线，便于脱离 NSApplication 测试。
//

import Foundation
import SwiftData

struct AppComposition {
    let settings: SettingsStore
    let panel: PanelAssembly
    let controller: ClipboardPanelController
    let hotKey: HotKeyManager

    init(
        modelContainer: ModelContainer,
        settings: SettingsStore = SettingsStore(),
        hotKeyRegistrar: HotKeyRegistering? = nil,
        hotKeyEventMonitor: HotKeyEventMonitoring? = nil,
        hotKeyStorage: SettingsStorage? = nil
    ) {
        self.settings = settings

        let panel = PanelAssembly(modelContainer: modelContainer, settings: settings)
        settings.observeRetentionChanges { [weak manager = panel.manager] _ in
            manager?.trimToRetention()
        }
        self.panel = panel
        self.controller = panel.makeController()

        // 默认 ⌃⌘V；按下按鼠标位置唤出/收起面板。
        let hotKey = HotKeyManager(
            onTrigger: { [weak controller = self.controller] in
                controller?.toggle(anchor: .mouse)
            },
            registrar: hotKeyRegistrar,
            eventMonitor: hotKeyEventMonitor,
            storage: hotKeyStorage ?? UserDefaults.standard
        )
        hotKey.reapply()
        self.hotKey = hotKey
    }
}
