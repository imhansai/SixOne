//
//  SettingsStoreTests.swift
//  SixOneTests

import Foundation
import Testing
@testable import SixOne

@Suite("设置存储")
@MainActor
struct SettingsStoreTests {
    private func makeStore(
        _ initial: [String: Any] = [:]
    ) -> (store: SettingsStore, storage: InMemorySettingsStorage) {
        let storage = InMemorySettingsStorage(initial)
        return (SettingsStore(storage: storage), storage)
    }

    @Test("读：没存过时落到默认档位、跟随系统语言与默认忽略列表")
    func defaultsWhenNothingStored() {
        let (store, _) = makeStore()

        #expect(store.historyRetention == SettingsStore.defaultRetention)
        #expect(store.storageLimit == SettingsStore.defaultStorageLimit)
        #expect(store.language == .system)
        #expect(store.ignoredApps.map(\.bundleIdentifier) == [
            "com.apple.Passwords", "com.apple.keychainaccess",
        ])
    }

    @Test("读：非法值一律回落默认，不崩")
    func fallsBackOnGarbage() {
        let (store, _) = makeStore([
            "historyRetention": 99,
            "historyStorageLimit": 99,
            "appLanguage": "kl",
            "privacyIgnoredApps": Data("not json".utf8),
        ])

        #expect(store.historyRetention == SettingsStore.defaultRetention)
        #expect(store.storageLimit == SettingsStore.defaultStorageLimit)
        #expect(store.language == .system)
        #expect(store.ignoredApps.count == 2, "解码失败回落默认忽略列表")
    }

    @Test("写：改档位落盘并回调一次")
    func writesRetentionAndNotifies() {
        let (store, storage) = makeStore()
        var notified = 0
        store.observeMaintenanceChanges { notified += 1 }

        store.historyRetention = .oneYear

        #expect(storage.object(forKey: "historyRetention") as? Int == HistoryRetention.oneYear.rawValue)
        #expect(notified == 1)
    }

    @Test("维护设置变化通知每个订阅者都收到")
    func notifiesEveryMaintenanceObserver() {
        let (store, _) = makeStore()
        var first = 0
        var second = 0
        store.observeMaintenanceChanges { first += 1 }
        store.observeMaintenanceChanges { second += 1 }

        store.historyRetention = .oneYear
        store.storageLimit = .gigabytes5

        #expect(first == 2)
        #expect(second == 2)
    }

    @Test("写：存储上限落盘并触发一次维护回调")
    func writesStorageLimitAndNotifies() {
        let (store, storage) = makeStore()
        var notified = 0
        store.observeMaintenanceChanges { notified += 1 }

        store.storageLimit = .gigabytes5

        #expect(storage.object(forKey: "historyStorageLimit") as? Int
            == HistoryStorageLimit.gigabytes5.rawValue)
        #expect(notified == 1)
    }

    @Test("存储上限相等赋值不落盘、不回调")
    func equalStorageLimitAssignmentIsIgnored() {
        let (store, storage) = makeStore()
        store.storageLimit = .gigabytes5
        let writesAfterFirst = storage.setCount
        var notified = 0
        store.observeMaintenanceChanges { notified += 1 }

        store.storageLimit = .gigabytes5

        #expect(storage.setCount == writesAfterFirst)
        #expect(notified == 0)
    }

    @Test("相等赋值不落盘、不回调：滑块会重复写同一个档位")
    func equalAssignmentIsIgnored() {
        let (store, storage) = makeStore()
        store.historyRetention = .sixMonths
        let writesAfterFirst = storage.setCount
        var notified = 0
        store.observeMaintenanceChanges { notified += 1 }

        store.historyRetention = .sixMonths
        store.historyRetention = .sixMonths

        #expect(storage.setCount == writesAfterFirst, "相等赋值不该再写盘")
        #expect(notified == 0, "相等赋值不该再触发一次裁剪")
    }

    @Test("相等赋值对语言同样不落盘")
    func equalLanguageAssignmentIsIgnored() {
        let (store, storage) = makeStore()
        store.language = .english
        let writesAfterFirst = storage.setCount

        store.language = .english

        #expect(storage.setCount == writesAfterFirst)
    }

    @Test("写：忽略列表按 JSON 落盘，重开能读回来")
    func persistsIgnoredApps() {
        let (store, storage) = makeStore()
        store.ignoredApps = [
            IgnoredApplication(bundleIdentifier: "com.example.a", displayName: "A", path: "/tmp/A.app"),
        ]

        let reopened = SettingsStore(storage: storage)

        #expect(reopened.ignoredApps.map(\.bundleIdentifier) == ["com.example.a"])
        #expect(reopened.ignoredApps.first?.displayName == "A")
    }

    @Test("恢复默认忽略列表")
    func restoresDefaultIgnoredApps() {
        let (store, _) = makeStore()
        store.ignoredApps = []

        store.restoreDefaultIgnoredApps()

        #expect(store.ignoredApps.count == 2)
    }
}
