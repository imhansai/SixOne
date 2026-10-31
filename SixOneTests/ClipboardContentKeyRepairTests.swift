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
}
