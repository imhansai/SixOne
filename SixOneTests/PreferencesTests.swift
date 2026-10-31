//
//  PreferencesTests.swift
//  SixOneTests
//  配置门面：默认值、旧 key 兼容与读写回环。
//

import Foundation
import Testing
@testable import SixOne

@Suite("配置门面")
@MainActor
struct PreferencesTests {
    @Test("空存储回落到默认值")
    func defaults() {
        let preferences = Preferences(storage: InMemorySettingsStorage())

        #expect(preferences.historyRetention == Preferences.defaultRetention)
        #expect(preferences.language == .system)
        #expect(preferences.hotKey == HotKeySettings.default)
        #expect(preferences.ignoredAppsData == nil)
    }

    @Test("沿用既有 key，升级后配置照常读得到")
    func readsLegacyKeys() {
        let storage = InMemorySettingsStorage([
            "historyRetention": HistoryRetention.unlimited.rawValue,
            "appLanguage": AppLanguage.english.rawValue,
            "privacyIgnoredApps": Data([1, 2, 3]),
            "globalHotKeyConfigured": false,
            "globalHotKeyCode": 8,
            "globalHotKeyModifiers": 0x0100,
        ])

        let preferences = Preferences(storage: storage)

        #expect(preferences.historyRetention == .unlimited)
        #expect(preferences.language == .english)
        #expect(preferences.ignoredAppsData == Data([1, 2, 3]))
        #expect(preferences.hotKey == HotKeySettings(
            isConfigured: false,
            keyCode: 8,
            modifiers: 0x0100
        ))
    }

    @Test("写入后能原样读回")
    func roundTrip() {
        let storage = InMemorySettingsStorage()
        let preferences = Preferences(storage: storage)

        preferences.historyRetention = .oneYear
        preferences.language = .simplifiedChinese
        preferences.ignoredAppsData = Data([4, 5])
        preferences.hotKey = HotKeySettings(
            isConfigured: true,
            keyCode: 7,
            modifiers: 0x0200
        )

        let reopened = Preferences(storage: storage)
        #expect(reopened.historyRetention == .oneYear)
        #expect(reopened.language == .simplifiedChinese)
        #expect(reopened.ignoredAppsData == Data([4, 5]))
        #expect(reopened.hotKey == HotKeySettings(
            isConfigured: true,
            keyCode: 7,
            modifiers: 0x0200
        ))
    }
}
