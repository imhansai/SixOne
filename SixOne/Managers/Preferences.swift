//
//  Preferences.swift
//  SixOne
//
//  配置读写门面：保留既有 UserDefaults key，设置、快捷键与语言共用一套存储口。
//

import Foundation

/// 快捷键配置原样落盘的三元组。
struct HotKeySettings: Equatable {
    static let defaultKeyCode: UInt32 = 9
    static let defaultModifiers = ModifierMasks.cmd | ModifierMasks.control
    static var `default`: HotKeySettings {
        HotKeySettings(isConfigured: true, keyCode: defaultKeyCode, modifiers: defaultModifiers)
    }

    var isConfigured: Bool
    var keyCode: UInt32
    var modifiers: UInt32
}

final class Preferences {
    /// 保留旧 key 名称，升级后已有配置照常读得到。
    private enum Key {
        static let retention = "historyRetention"
        static let ignoredApps = "privacyIgnoredApps"
        static let hotKeyConfigured = "globalHotKeyConfigured"
        static let hotKeyCode = "globalHotKeyCode"
        static let hotKeyModifiers = "globalHotKeyModifiers"
    }

    static let defaultRetention: HistoryRetention = .threeMonths

    private let storage: SettingsStorage

    init(storage: SettingsStorage = UserDefaults.standard) {
        self.storage = storage
    }

    var historyRetention: HistoryRetention {
        get {
            let raw = storage.object(forKey: Key.retention) as? Int
            return raw.flatMap(HistoryRetention.init(rawValue:)) ?? Self.defaultRetention
        }
        set {
            storage.set(newValue.rawValue, forKey: Key.retention)
        }
    }

    var language: AppLanguage {
        get {
            let raw = storage.object(forKey: AppLanguage.storageKey) as? String ?? ""
            return AppLanguage(rawValue: raw) ?? .system
        }
        set {
            storage.set(newValue.rawValue, forKey: AppLanguage.storageKey)
        }
    }

    var ignoredAppsData: Data? {
        get { storage.object(forKey: Key.ignoredApps) as? Data }
        set { storage.set(newValue, forKey: Key.ignoredApps) }
    }

    var hotKey: HotKeySettings {
        get {
            let hasSavedConfiguration = storage.object(forKey: Key.hotKeyConfigured) != nil
            let configured = hasSavedConfiguration
                ? (storage.object(forKey: Key.hotKeyConfigured) as? Bool ?? false)
                : true
            let keyCode = UInt32(
                storage.object(forKey: Key.hotKeyCode) as? Int
                    ?? Int(HotKeySettings.defaultKeyCode)
            )
            let modifiers = UInt32(
                storage.object(forKey: Key.hotKeyModifiers) as? Int
                    ?? Int(HotKeySettings.defaultModifiers)
            )
            return HotKeySettings(
                isConfigured: configured,
                keyCode: keyCode,
                modifiers: modifiers
            )
        }
        set {
            storage.set(newValue.isConfigured, forKey: Key.hotKeyConfigured)
            storage.set(Int(newValue.keyCode), forKey: Key.hotKeyCode)
            storage.set(Int(newValue.modifiers), forKey: Key.hotKeyModifiers)
        }
    }
}
