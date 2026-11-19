//
//  SchemaMigrationTests.swift
//  SixOneTests
//  V1 库升级到当前版本：数据不丢，派生快照补齐，重复打开保持稳定。
//

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("历史库迁移")
@MainActor
struct SchemaMigrationTests {
    @Test("V1 库升级后条目保留，缺失的去重与搜索快照被补齐")
    func migratesV1AndBackfillsDerivedSnapshots() throws {
        let fixture = try MigrationFixture()
        defer { fixture.cleanUp() }

        let seeded = try fixture.seedV1Store()

        let container = AppModelContainer.make(
            isStoredInMemoryOnly: false,
            storeURL: fixture.storeURL
        )
        let items = try container.mainContext.fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 3)

        let text = try #require(items.first { $0.id == seeded.textID })
        #expect(text.text == "legacy text")
        #expect(text.titleSnapshot == "legacy text")
        #expect(text.contentKeySnapshot != nil, "旧条目的去重 key 没有补齐")
        #expect(text.contentKeyVersion == SixOneSchemaV2.ClipboardItem.currentContentKeyVersion)
        #expect(text.searchText == "legacy text", "旧条目的搜索快照没有补齐")

        let file = try #require(items.first { $0.id == seeded.fileID })
        #expect(file.kind == .file)
        #expect(file.filePathsSearchText?.contains("legacy.txt") == true, "旧文件条目的路径快照没有补齐")
        #expect(file.contentKeySnapshot != nil)
        #expect(file.contentKeyVersion == SixOneSchemaV2.ClipboardItem.currentContentKeyVersion)

        let keyed = try #require(items.first { $0.id == seeded.keyedID })
        #expect(keyed.contentKeySnapshot == seeded.keyedSnapshot, "已有快照不该被重算覆盖")
        #expect(keyed.contentKeyVersion == nil, "健康条目不再逐行补版本号")
    }

    @Test("迁移后再次打开不会重复迁移或丢数据")
    func reopeningMigratedStoreKeepsData() throws {
        let fixture = try MigrationFixture()
        defer { fixture.cleanUp() }
        _ = try fixture.seedV1Store()

        _ = AppModelContainer.make(isStoredInMemoryOnly: false, storeURL: fixture.storeURL)

        let reopened = AppModelContainer.make(
            isStoredInMemoryOnly: false,
            storeURL: fixture.storeURL
        )
        let items = try reopened.mainContext.fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 3)
    }

    @Test("V2 库升级到 V3：旧缩略图保留，版本保持 nil 等待惰性重算")
    func migratesV2Thumbnails() throws {
        let fixture = try MigrationFixture()
        defer { fixture.cleanUp() }
        let seeded = try fixture.seedV2Store()

        let container = AppModelContainer.make(
            isStoredInMemoryOnly: false,
            storeURL: fixture.storeURL
        )
        let items = try container.mainContext.fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 2)

        let withThumbnail = try #require(items.first { $0.id == seeded.thumbnailID })
        #expect(withThumbnail.thumbnailData == Data([1, 2, 3]))
        #expect(withThumbnail.thumbnailVersion == nil)

        let withoutThumbnail = try #require(items.first { $0.id == seeded.plainID })
        #expect(withoutThumbnail.thumbnailVersion == nil)
    }

    @Test("V3 库升级到 V4：原有内容保留，别名为空")
    func migratesV3ToV4() throws {
        let fixture = try MigrationFixture()
        defer { fixture.cleanUp() }
        let seeded = try fixture.seedV3Store()

        let container = AppModelContainer.make(
            isStoredInMemoryOnly: false,
            storeURL: fixture.storeURL
        )
        let items = try container.mainContext.fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 1)

        let item = try #require(items.first { $0.id == seeded })
        #expect(item.text == "v3 text")
        #expect(item.alias == nil)
    }

    @Test("V4 库升级到 V5：原有内容保留，条目未分组，分组表为空")
    func migratesV4ToV5() throws {
        let fixture = try MigrationFixture()
        defer { fixture.cleanUp() }
        let seeded = try fixture.seedV4Store()

        let container = AppModelContainer.make(
            isStoredInMemoryOnly: false,
            storeURL: fixture.storeURL
        )
        let items = try container.mainContext.fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 1)

        let item = try #require(items.first { $0.id == seeded })
        #expect(item.text == "v4 text")
        #expect(item.alias == "旧别名")
        #expect(item.collectionID == nil)

        let collections = try container.mainContext.fetch(
            FetchDescriptor<ClipboardCollection>()
        )
        #expect(collections.isEmpty)
    }

    @Test("V5 库升级到 V6：条目与分组保留，旧分组从同一排序位置开始")
    func migratesV5ToV6() throws {
        let fixture = try MigrationFixture()
        defer { fixture.cleanUp() }
        let seeded = try fixture.seedV5Store()

        let container = AppModelContainer.make(
            isStoredInMemoryOnly: false,
            storeURL: fixture.storeURL
        )
        let items = try container.mainContext.fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 1)

        let item = try #require(items.first { $0.id == seeded.itemID })
        #expect(item.text == "v5 text")
        #expect(item.collectionID == seeded.collectionID)

        let collections = try container.mainContext.fetch(
            FetchDescriptor<ClipboardCollection>()
        )
        #expect(collections.map(\.id) == [seeded.collectionID])
        #expect(collections.map(\.sortOrder) == [0], "旧分组迁移后应从同一位置开始")
    }

    @Test("全新库按当前版本创建，写入后重新打开仍在")
    func freshStoreUsesCurrentSchema() throws {
        let fixture = try MigrationFixture()
        defer { fixture.cleanUp() }

        try fixture.seedCurrentStore()

        let reopened = AppModelContainer.make(
            isStoredInMemoryOnly: false,
            storeURL: fixture.storeURL
        )
        let items = try reopened.mainContext.fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.map(\.text) == ["fresh store"])
    }
}

@MainActor
private struct MigrationFixture {
    let directory: URL
    let storeURL: URL

    init() throws {
        directory = try TemporaryFiles.makeDirectory(prefix: "sixone-migration")
        storeURL = directory.appendingPathComponent(AppModelContainer.storeFileName)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 用冻结的 V1 schema 建库，并故意清掉派生快照，模拟旧版本数据。
    func seedV1Store() throws -> (
        textID: UUID,
        fileID: UUID,
        keyedID: UUID,
        keyedSnapshot: String
    ) {
        let schema = Schema(versionedSchema: SixOneSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let text = SixOneSchemaV1.ClipboardItem(kind: .text, text: "legacy text")
        text.refreshTitleSnapshot()
        text.contentKeySnapshot = nil
        text.searchText = nil
        text.filePathsSearchText = nil
        context.insert(text)

        let file = SixOneSchemaV1.ClipboardItem(kind: .file, filePaths: ["/tmp/legacy.txt"])
        file.refreshTitleSnapshot()
        file.contentKeySnapshot = nil
        file.searchText = nil
        file.filePathsSearchText = nil
        context.insert(file)

        // 已有去重快照的旧条目：迁移只补版本号，不应重算覆盖。
        let keyed = SixOneSchemaV1.ClipboardItem(kind: .text, text: "already keyed")
        keyed.refreshTitleSnapshot()
        let keyedSnapshot = keyed.refreshContentKey()
        context.insert(keyed)

        try context.save()
        return (text.id, file.id, keyed.id, keyedSnapshot)
    }

    /// 用冻结的 V2 schema 建库，带一条旧缩略图和一条无缩略图条目。
    func seedV2Store() throws -> (thumbnailID: UUID, plainID: UUID) {
        let schema = Schema(versionedSchema: SixOneSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let withThumbnail = SixOneSchemaV2.ClipboardItem(
            kind: .image,
            imageData: Data([9, 9]),
            thumbnailData: Data([1, 2, 3]),
            contentType: "PNG"
        )
        withThumbnail.refreshTitleSnapshot()
        withThumbnail.refreshContentKey()
        context.insert(withThumbnail)

        let plain = SixOneSchemaV2.ClipboardItem(kind: .text, text: "no thumbnail")
        plain.refreshTitleSnapshot()
        plain.refreshContentKey()
        context.insert(plain)

        try context.save()
        return (withThumbnail.id, plain.id)
    }

    /// 用冻结的 V3 schema 建库，验证新增别名字段的轻量迁移。
    func seedV3Store() throws -> UUID {
        let schema = Schema(versionedSchema: SixOneSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let item = SixOneSchemaV3.ClipboardItem(kind: .text, text: "v3 text")
        item.refreshTitleSnapshot()
        item.refreshContentKey()
        context.insert(item)

        try context.save()
        return item.id
    }

    /// 用冻结的 V4 schema 建库，验证新增分组归属与分组表的轻量迁移。
    func seedV4Store() throws -> UUID {
        let schema = Schema(versionedSchema: SixOneSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let item = SixOneSchemaV4.ClipboardItem(kind: .text, text: "v4 text")
        item.refreshTitleSnapshot()
        item.refreshContentKey()
        item.alias = "旧别名"
        context.insert(item)

        try context.save()
        return item.id
    }

    /// 用冻结的 V5 schema 建库，验证新增分组排序位置的轻量迁移。
    func seedV5Store() throws -> (itemID: UUID, collectionID: UUID) {
        let schema = Schema(versionedSchema: SixOneSchemaV5.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let collection = SixOneSchemaV5.ClipboardCollection(name: "旧分组")
        context.insert(collection)

        let item = SixOneSchemaV5.ClipboardItem(
            kind: .text,
            text: "v5 text",
            collectionID: collection.id
        )
        item.refreshTitleSnapshot()
        item.refreshContentKey()
        context.insert(item)

        try context.save()
        return (item.id, collection.id)
    }

    func seedCurrentStore() throws {
        let container = AppModelContainer.make(
            isStoredInMemoryOnly: false,
            storeURL: storeURL
        )
        let context = container.mainContext
        let item = ClipboardItem(kind: .text, text: "fresh store")
        item.refreshTitleSnapshot()
        item.refreshContentKey()
        context.insert(item)
        try context.save()
    }
}
