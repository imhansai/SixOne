//
//  StorageBudgetIntegrationTests.swift
//  SixOneTests
//  真实落盘库的外部存储预算：统计、裁剪与磁盘回收。
//

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("外部存储预算（真实落盘）")
@MainActor
struct StorageBudgetIntegrationTests {
    @Test("真实库：统计到外部数据；超预算删除后回收磁盘并保留最新一条")
    func trimsRealStoreAndReclaimsDisk() async throws {
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-budget-real")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(AppModelContainer.storeFileName)
        let schema = Schema([ClipboardItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let context = container.mainContext

        // 每条 4 MB，确保 SwiftData 走 `.externalStorage`。
        let chunk = Data(repeating: 0x41, count: 4 * 1024 * 1024)
        var ids: [UUID] = []
        for _ in 0..<4 {
            let item = ClipboardItem(kind: .image, imageData: chunk, contentType: "PNG")
            context.insert(item)
            ids.append(item.id)
        }
        try context.save()

        let externalURL = ExternalStorageDirectory.url(forStoreAt: storeURL)
        #expect(FileManager.default.fileExists(atPath: externalURL.path), "外部存储目录没有生成")
        let before = await ExternalStorageDirectory.byteCount(forStoreAt: storeURL)
        #expect(before > 0, "外部存储没有实际落盘，无法验证预算")

        let result = await HistoryMaintenance(container: container)
            .trimToExternalStorageBudget(limit: 0)
        #expect(result.deletedCount == 3)

        let readContext = ModelContext(container)
        #expect(try readContext.fetchCount(FetchDescriptor<ClipboardItem>()) == 1)
        var newest = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.recencyID, order: .reverse)]
        )
        newest.fetchLimit = 1
        #expect(try readContext.fetch(newest).first?.id == ids.last)

        let after = await ExternalStorageDirectory.byteCount(forStoreAt: storeURL)
        #expect(after < before, "删除后外部文件没有释放")
        #expect(after <= Int64(chunk.count) * 2, "只应保留最新一条的外部数据")
    }
}
