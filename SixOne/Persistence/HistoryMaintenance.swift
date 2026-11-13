//
//  HistoryMaintenance.swift
//  SixOne
//  后台维护：保留期与外部存储预算裁剪、清空历史；独立上下文执行。
//

import Foundation
import SwiftData
import os

nonisolated struct MaintenanceResult: Sendable, Equatable {
    var deletedCount = 0
    var failureReason: String?
}

actor HistoryMaintenance {
    private let container: ModelContainer
    private let externalByteCount: @Sendable () async -> Int64
    private let persist: @Sendable (ModelContext) throws -> Void
    private let logger = AppLog.logger("HistoryMaintenance")

    private static let retentionBatchSize = 500
    private static let budgetBatchSize = 50

    init(
        container: ModelContainer,
        externalByteCount: (@Sendable () async -> Int64)? = nil,
        persist: (@Sendable (ModelContext) throws -> Void)? = nil
    ) {
        self.container = container
        self.externalByteCount = externalByteCount ?? { await Self.storeByteCount(for: container) }
        self.persist = persist ?? { try $0.save() }
    }

    /// 按最后活动时间裁剪；nil 表示不限。
    func trimToRetention(interval: TimeInterval?) async -> MaintenanceResult {
        guard let interval else { return MaintenanceResult() }
        let cutoff = Date().addingTimeInterval(-interval)
        let context = ModelContext(container)
        var deleted = 0
        while true {
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.lastActivityAt < cutoff }
            )
            descriptor.fetchLimit = Self.retentionBatchSize
            let batch: [ClipboardItem]
            do {
                batch = try context.fetch(descriptor)
            } catch {
                return failure("裁剪过期条目", error, deleted: deleted)
            }
            guard !batch.isEmpty else { break }
            for item in batch {
                context.delete(item)
            }
            do {
                try persist(context)
            } catch {
                return failure("裁剪过期条目", error, deleted: deleted)
            }
            deleted += batch.count
            await Task.yield()
        }
        return MaintenanceResult(deletedCount: deleted)
    }

    /// 外部存储超预算时从最旧条目删起，始终保留最新一条；nil 表示不限。
    func trimToExternalStorageBudget(limit: Int64?) async -> MaintenanceResult {
        guard let limit else { return MaintenanceResult() }
        var bytes = await externalByteCount()
        guard bytes > limit else { return MaintenanceResult() }

        let context = ModelContext(container)
        guard let total = itemCount(in: context), total > 1,
              let newestID = newestItemID(in: context) else {
            return MaintenanceResult()
        }

        var remaining = total
        var deleted = 0
        while bytes > limit, remaining > 1 {
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.imageData != nil || $0.attributedTextData != nil },
                sortBy: [SortDescriptor(\.recencyID)]
            )
            descriptor.fetchLimit = Self.budgetBatchSize
            descriptor.propertiesToFetch = [\.id]
            let batch: [ClipboardItem]
            do {
                batch = try context.fetch(descriptor)
            } catch {
                return failure("按外部存储预算裁剪", error, deleted: deleted)
            }
            let deletable = batch.filter { $0.id != newestID }
            guard !deletable.isEmpty else { break }
            for item in deletable {
                context.delete(item)
            }
            do {
                try persist(context)
            } catch {
                return failure("按外部存储预算裁剪", error, deleted: deleted)
            }
            remaining -= deletable.count
            deleted += deletable.count
            bytes = await externalByteCount()
            await Task.yield()
        }
        return MaintenanceResult(deletedCount: deleted)
    }

    func clearAll() async -> MaintenanceResult {
        let context = ModelContext(container)
        var cursor: UUID?
        var deleted = 0
        do {
            while true {
                var descriptor = FetchDescriptor<ClipboardItem>(
                    sortBy: [SortDescriptor(\.recencyID)]
                )
                if let cursor {
                    descriptor.predicate = #Predicate { $0.recencyID > cursor }
                }
                descriptor.fetchLimit = Self.retentionBatchSize
                let batch = try context.fetch(descriptor)
                guard !batch.isEmpty else { break }
                for item in batch {
                    context.delete(item)
                }
                cursor = batch.last?.recencyID
                deleted += batch.count
            }
            guard deleted > 0 else { return MaintenanceResult() }
            try persist(context)
        } catch {
            return failure("清空历史", error, deleted: 0)
        }
        return MaintenanceResult(deletedCount: deleted)
    }

    private func failure(_ reason: String, _ error: Error, deleted: Int) -> MaintenanceResult {
        logger.error("\(reason)失败：\(error.localizedDescription, privacy: .public)")
        return MaintenanceResult(deletedCount: deleted, failureReason: reason)
    }

    private func itemCount(in context: ModelContext) -> Int? {
        do {
            return try context.fetchCount(FetchDescriptor<ClipboardItem>())
        } catch {
            logger.error("预算裁剪：计数失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func newestItemID(in context: ModelContext) -> UUID? {
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.recencyID, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.id]
        do {
            return try context.fetch(descriptor).first?.id
        } catch {
            logger.error("预算裁剪：查询最新条目失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private nonisolated static func storeByteCount(for container: ModelContainer) async -> Int64 {
        guard let url = container.configurations
            .first(where: { !$0.isStoredInMemoryOnly })?.url else { return 0 }
        return await ExternalStorageDirectory.byteCount(forStoreAt: url)
    }
}
