//
//  MigrationBenchmarkTests.swift
//  SixOneTests
//  默认跳过；写入 /tmp/sixone-benchmark 或 .benchmark-history 后跑大库升级基准。
//

import AppKit
import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("迁移规模基准")
@MainActor
struct MigrationBenchmarkTests {
    /// 迁移基准最多用 5 万条，避免开关设成 20 万时把两套库都写一遍。
    private static let maxItems = 50_000
    private static let docThumbnail = Data(repeating: 0xAA, count: 600)
    private static let photoThumbnail = Data(repeating: 0xBB, count: 4_000)

    @Test(
        "V1/V2 大库升级到 V3 的打开与迁移耗时",
        .enabled(if: HistoryBenchmarkSwitch.itemCount != nil)
    )
    func measuresMigration() throws {
        let configured = try #require(HistoryBenchmarkSwitch.itemCount)
        let count = min(configured, Self.maxItems)
        print("BENCHMIG ==== 条目数 \(count)（开关 \(configured)） ====")

        let fixture = try MigrationBenchmarkFixture()
        defer { fixture.cleanUp() }

        try Self.measure("预置 V1 库 \(count) 条") {
            try Self.seedV1Store(at: fixture.v1StoreURL, count: count)
        }
        print("BENCHMIG V1 库体积：\(Self.megabytes(fixture.size(of: fixture.v1StoreURL))) MB")

        var container: ModelContainer? = Self.measure("V1 → V3 打开/迁移") {
            AppModelContainer.make(isStoredInMemoryOnly: false, storeURL: fixture.v1StoreURL)
        }
        try Self.verify(container, count: count)
        container = nil

        _ = Self.measure("V1 迁移后再次打开") {
            AppModelContainer.make(isStoredInMemoryOnly: false, storeURL: fixture.v1StoreURL)
        }

        try Self.measure("预置 V2 库 \(count) 条") {
            try Self.seedV2Store(at: fixture.v2StoreURL, count: count)
        }
        print("BENCHMIG V2 库体积：\(Self.megabytes(fixture.size(of: fixture.v2StoreURL))) MB")

        var migrated: ModelContainer? = Self.measure("V2 → V3 打开/迁移") {
            AppModelContainer.make(isStoredInMemoryOnly: false, storeURL: fixture.v2StoreURL)
        }
        try Self.verify(migrated, count: count)
        migrated = nil

        _ = Self.measure("V2 迁移后再次打开") {
            AppModelContainer.make(isStoredInMemoryOnly: false, storeURL: fixture.v2StoreURL)
        }
        print("BENCHMIG 迁移后库体积：\(Self.megabytes(fixture.size(of: fixture.v2StoreURL))) MB")
    }

    // MARK: - 预置

    private static func seedV1Store(at url: URL, count: Int) throws {
        let schema = Schema(versionedSchema: SixOneSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        for start in stride(from: 0, to: count, by: 2000) {
            for index in start..<min(start + 2000, count) {
                let item: SixOneSchemaV1.ClipboardItem
                switch index % 10 {
                case 7, 8:
                    item = SixOneSchemaV1.ClipboardItem(
                        kind: .file,
                        thumbnailData: Self.docThumbnail,
                        filePaths: ["/tmp/基准/文件\(index).pdf"]
                    )
                case 9:
                    item = SixOneSchemaV1.ClipboardItem(
                        kind: .image,
                        imageData: Data(repeating: UInt8(index % 251), count: 8 * 1024),
                        thumbnailData: Self.photoThumbnail,
                        contentType: "PNG"
                    )
                default:
                    item = SixOneSchemaV1.ClipboardItem(
                        kind: .text,
                        text: "第 \(index) 条历史：迁移基准正文，用来量派生快照回填成本。"
                    )
                }
                item.refreshTitleSnapshot()
                item.refreshContentKey()
                context.insert(item)
            }
            try context.save()
        }
    }

    private static func seedV2Store(at url: URL, count: Int) throws {
        let schema = Schema(versionedSchema: SixOneSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        for start in stride(from: 0, to: count, by: 2000) {
            for index in start..<min(start + 2000, count) {
                let item: SixOneSchemaV2.ClipboardItem
                switch index % 10 {
                case 7, 8:
                    item = SixOneSchemaV2.ClipboardItem(
                        kind: .file,
                        thumbnailData: Self.docThumbnail,
                        filePaths: ["/tmp/基准/文件\(index).pdf"]
                    )
                case 9:
                    item = SixOneSchemaV2.ClipboardItem(
                        kind: .image,
                        imageData: Data(repeating: UInt8(index % 251), count: 8 * 1024),
                        thumbnailData: Self.photoThumbnail,
                        contentType: "PNG"
                    )
                default:
                    item = SixOneSchemaV2.ClipboardItem(
                        kind: .text,
                        text: "第 \(index) 条历史：迁移基准正文，用来量派生快照回填成本。"
                    )
                }
                item.refreshTitleSnapshot()
                item.refreshContentKey()
                context.insert(item)
            }
            try context.save()
        }
    }

    // MARK: - 校验与计时

    private static func verify(_ container: ModelContainer?, count: Int) throws {
        let container = try #require(container)
        let context = container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<ClipboardItem>()) == count)

        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.thumbnailData != nil }
        )
        descriptor.fetchLimit = 1
        let sample = try #require(try context.fetch(descriptor).first)
        #expect(sample.thumbnailVersion == nil)
    }

    @discardableResult
    private static func measure<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        let value = try body()
        let duration = ContinuousClock.now - start
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1e15
        print("BENCHMIG \(label): \(String(format: "%.2f", milliseconds)) ms")
        return value
    }

    private static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576)
    }
}

@MainActor
private struct MigrationBenchmarkFixture {
    let directory: URL
    let v1StoreURL: URL
    let v2StoreURL: URL

    init() throws {
        directory = try TemporaryFiles.makeDirectory(prefix: "sixone-migration-bench")
        v1StoreURL = directory.appendingPathComponent("V1.store")
        v2StoreURL = directory.appendingPathComponent("V2.store")
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    func size(of url: URL) -> Int64 {
        ["", "-wal", "-shm"].reduce(0) { total, suffix in
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: url.path + suffix
            )
            return total + ((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }
}
