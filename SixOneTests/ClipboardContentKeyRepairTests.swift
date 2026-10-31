//
//  ClipboardContentKeyRepairTests.swift
//  SixOneTests
//  图片去重 key 升级：旧版本条目后台重算，已是最新版本的不动。
//

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("图片去重 key 重算")
@MainActor
struct ClipboardContentKeyRepairTests {
    @Test("旧版本图片重算为全量哈希，当前版本保持原样")
    func repairsLegacyImageKeys() async throws {
        let schema = Schema([ClipboardItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let legacyData = Data(repeating: 0x11, count: 200)
        let nilData = Data(repeating: 0x22, count: 200)
        let currentData = Data(repeating: 0x33, count: 200)

        let legacy = ClipboardItem(kind: .image, imageData: legacyData)
        legacy.contentKeySnapshot = "legacy-key"
        legacy.contentKeyVersion = 1
        context.insert(legacy)

        let nilVersion = ClipboardItem(kind: .image, imageData: nilData)
        nilVersion.contentKeySnapshot = "nil-key"
        context.insert(nilVersion)

        let current = ClipboardItem(kind: .image, imageData: currentData)
        current.contentKeySnapshot = "current-key"
        current.contentKeyVersion = ClipboardItem.currentContentKeyVersion
        context.insert(current)

        try context.save()

        await ClipboardContentKeyRepair(container: container).runIfNeeded()

        let verification = ModelContext(container)
        let items = try verification.fetch(FetchDescriptor<ClipboardItem>())
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        let repairedLegacy = try #require(byID[legacy.id])
        #expect(repairedLegacy.contentKeyVersion == ClipboardItem.currentContentKeyVersion)
        #expect(repairedLegacy.contentKeySnapshot == ClipboardItem.contentKey(
            kind: .image,
            text: nil,
            imageData: legacyData,
            filePaths: []
        ))

        let repairedNil = try #require(byID[nilVersion.id])
        #expect(repairedNil.contentKeyVersion == ClipboardItem.currentContentKeyVersion)
        #expect(repairedNil.contentKeySnapshot == ClipboardItem.contentKey(
            kind: .image,
            text: nil,
            imageData: nilData,
            filePaths: []
        ))

        let untouched = try #require(byID[current.id])
        #expect(untouched.contentKeySnapshot == "current-key")
        #expect(untouched.contentKeyVersion == ClipboardItem.currentContentKeyVersion)
    }

    @Test("标记已到当前版本后跳过扫描，健康库不再每次启动全表查")
    func markerSkipsHealthyStore() async throws {
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-repair-marker")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("SixOne.store")
        let container = AppModelContainer.make(isStoredInMemoryOnly: false, storeURL: storeURL)
        let context = container.mainContext

        let legacy = ClipboardItem(kind: .image, imageData: Data(repeating: 0x44, count: 64))
        legacy.contentKeyVersion = 1
        legacy.contentKeySnapshot = "old"
        context.insert(legacy)
        try context.save()

        let suite = "sixone-repair-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let marker = UserDefaultsContentKeyRepairMarker(defaults: defaults, key: "version")

        await ClipboardContentKeyRepair(container: container, marker: marker).runIfNeeded()
        var verification = ModelContext(container)
        let repaired = try #require(verification.fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(repaired.contentKeyVersion == ClipboardItem.currentContentKeyVersion)

        // 标记已到位：再放进一条旧版本条目，本轮不应再扫描修复。
        let legacyAgain = ClipboardItem(kind: .image, imageData: Data(repeating: 0x55, count: 64))
        legacyAgain.contentKeyVersion = 1
        legacyAgain.contentKeySnapshot = "old-again"
        context.insert(legacyAgain)
        try context.save()

        await ClipboardContentKeyRepair(container: container, marker: marker).runIfNeeded()

        verification = ModelContext(container)
        let rows = try verification.fetch(FetchDescriptor<ClipboardItem>())
        let untouched = try #require(rows.first { $0.id == legacyAgain.id })
        #expect(untouched.contentKeyVersion == 1, "标记命中后仍执行了扫描")
    }
}
