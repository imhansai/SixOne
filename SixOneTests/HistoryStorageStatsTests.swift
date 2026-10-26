//
//  HistoryStorageStatsTests.swift
//  SixOneTests
//  存储概况：条数取实际行数，空间只算历史库目录。

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("历史概况")
@MainActor
struct HistoryStorageStatsTests {
    @Test("条数取自库里实际行数，内存库没有磁盘占用")
    func countsRowsAndReportsNoDiskUseForMemoryStore() async throws {
        let container = try makeMemoryContainer()
        let context = container.mainContext
        for index in 0..<3 {
            context.insert(ClipboardItem(kind: .text, text: "item \(index)"))
        }
        try context.save()

        let stats = await HistoryStorageStatsReader.read(container: container)

        #expect(stats.itemCount == 3)
        #expect(stats.byteCount == nil, "内存库没有库文件，空间应为未知")
    }

    @Test("文件库读得到条数与非零占用，外部附件计入空间")
    func readsCountAndDiskUseForFileStore() async throws {
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-stats")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(AppModelContainer.storeFileName)
        let container = AppModelContainer.make(isStoredInMemoryOnly: false, storeURL: storeURL)
        let context = container.mainContext
        context.insert(ClipboardItem(kind: .text, text: "hello"))
        context.insert(ClipboardItem(kind: .text, text: "world"))
        // 位图走 externalStorage：在库文件外，仍在统计目录内。
        context.insert(ClipboardItem(kind: .image, imageData: Data(repeating: 0xA5, count: 512 * 1024)))
        try context.save()

        let stats = await HistoryStorageStatsReader.read(container: container)

        #expect(stats.itemCount == 3)
        let byteCount = try #require(stats.byteCount)
        #expect(byteCount >= 512 * 1024, "外部附件没有计入占用，实际 \(byteCount) 字节")
    }

    @Test("空间按目录内全部普通文件累加，隐藏子目录与空目录一并处理")
    func sumsAllRegularFilesInDirectory() throws {
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-stats-size")
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(repeating: 0, count: 1_000)
            .write(to: directory.appendingPathComponent("SixOne.store"))
        let external = directory
            .appendingPathComponent(".SixOne.store_SUPPORT/_EXTERNAL_DATA", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 2_000)
            .write(to: external.appendingPathComponent("blob"))
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("empty", isDirectory: true),
            withIntermediateDirectories: true
        )

        #expect(HistoryStorageStatsReader.byteCount(in: directory) == 3_000)
    }

    private func makeMemoryContainer() throws -> ModelContainer {
        let schema = Schema([ClipboardItem.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }
}
