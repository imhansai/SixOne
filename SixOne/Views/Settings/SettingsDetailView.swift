//
//  SettingsDetailView.swift
//  SixOne
//
//  设置详情区：按当前面板选内容视图，并作为窗口标题的唯一写者。
//

import SwiftUI

struct SettingsDetailView: View {
    let navigation: SettingsNavigation
    let settings: SettingsStore
    let hotKeyManager: HotKeyManager
    let loadStorageStats: () async -> HistoryStorageStats
    let onClearHistory: () -> Void

    var body: some View {
        Form {
            switch navigation.current {
            case .general:
                GeneralSettingsView(settings: settings)
            case .storage:
                StorageSettingsView(
                    settings: settings,
                    loadStats: loadStorageStats,
                    onClearHistory: onClearHistory
                )
            case .privacy:
                PrivacySettingsView(settings: settings)
            case .shortcuts:
                ShortcutsSettingsView(hotKeyManager: hotKeyManager)
            case .about:
                AboutSettingsView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(navigation.current.title)
    }
}
