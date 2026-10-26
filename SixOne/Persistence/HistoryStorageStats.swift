//
//  HistoryStorageStats.swift
//  SixOne
//
//  存储页概况：历史条数与库目录磁盘占用；内存库没有占用，空间为 nil。
//

import Foundation
import os
import SwiftData

/// 一次概况读数；nil 表示读不到。
nonisolated struct HistoryStorageStats: Equatable, Sendable {
    let itemCount: Int?
    let byteCount: Int64?
}

nonisolated enum HistoryStorageStatsReader {
    private static let logger = AppLog.logger("Persistence")

    /// 读取一次；计数与遍历并行。
    static func read(container: ModelContainer) async -> HistoryStorageStats {
        let storeURL = diskStoreURL(for: container)
        async let itemCount = countItems(in: container)
        async let byteCount = storeByteCount(storeURL: storeURL)
        return await HistoryStorageStats(itemCount: itemCount, byteCount: byteCount)
    }

    /// 落盘库位置；内存库为 nil。
    static func diskStoreURL(for container: ModelContainer) -> URL? {
        container.configurations
            .first { !$0.isStoredInMemoryOnly }?
            .url
    }

    // MARK: - 条数

    private static func countItems(in container: ModelContainer) async -> Int? {
        await Task.detached(priority: .utility) {
            do {
                return try ModelContext(container).fetchCount(FetchDescriptor<ClipboardItem>())
            } catch {
                logger.error("读取历史条数失败：\(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    // MARK: - 磁盘占用

    private static func storeByteCount(storeURL: URL?) async -> Int64? {
        guard let storeURL else { return nil }
        let directory = storeURL.deletingLastPathComponent()
        return await Task.detached(priority: .utility) {
            byteCount(in: directory)
        }.value
    }

    /// 目录内普通文件总字节数；遍历失败的行跳过，统计偏小好过整块失败。
    static func byteCount(in directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else { continue }
            total += Int64(fileSize)
        }
        return total
    }
}
