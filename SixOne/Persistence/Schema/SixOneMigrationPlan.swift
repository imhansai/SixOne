//
//  SixOneMigrationPlan.swift
//  SixOne
//
//  历史库版本迁移：V1 → V2 补齐派生快照；V2 → V3 给旧缩略图打版本（V3 同时新增 id 索引）。
//

import Foundation
import SwiftData
import os

nonisolated enum SixOneMigrationPlan: SchemaMigrationPlan {
    private static let logger = AppLog.logger("Migration")

    static var schemas: [any VersionedSchema.Type] {
        [SixOneSchemaV1.self, SixOneSchemaV2.self, SixOneSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    /// 结构迁移由 SwiftData 完成；这里补旧条目缺失的派生快照。
    /// 补齐失败不回滚迁移：结构已经可用，派生快照缺失由读取路径兜底。
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SixOneSchemaV1.self,
        toVersion: SixOneSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            backfillV2Snapshots(in: context)
        }
    )

    /// V3 的 id 索引随目标模型落地；这里给 V2 已有的缩略图打上当前版本。
    static let migrateV2toV3 = MigrationStage.custom(
        fromVersion: SixOneSchemaV2.self,
        toVersion: SixOneSchemaV3.self,
        willMigrate: nil,
        didMigrate: { context in
            markLegacyThumbnails(in: context)
        }
    )

    private static func backfillV2Snapshots(in context: ModelContext) {
        // 这一阶段的目标库还是 V2，必须显式取 V2 模型，不能用指向 V3 的类型别名。
        var descriptor = FetchDescriptor<SixOneSchemaV2.ClipboardItem>(
            predicate: #Predicate { $0.contentKeyVersion == nil }
        )
        // 幂等快照都在时只补版本号；不预取位图/富文本，避免大库迁移一次性读满内存。
        descriptor.propertiesToFetch = [
            \.id, \.kindRaw, \.contentKeySnapshot, \.contentKeyVersion,
            \.searchText, \.filePathsSearchText, \.text, \.filePaths, \.filePath, \.colorData,
        ]
        guard let items = try? context.fetch(descriptor) else {
            logger.error("迁移后读取旧条目失败，跳过派生快照补齐")
            return
        }
        guard !items.isEmpty else { return }
        logger.notice("迁移补齐 \(items.count, privacy: .public) 条旧条目的派生快照")

        for item in items {
            if item.contentKeySnapshot == nil {
                item.refreshContentKey()
            } else {
                // V1 的快照由同一算法生成，只补版本号，避免为全部旧条目重读图片/正文。
                // 去重算法以后若变化，新版本迁移要按版本重算，而不是沿用旧快照。
                item.contentKeyVersion = SixOneSchemaV2.ClipboardItem.currentContentKeyVersion
            }
            if item.searchText == nil {
                if item.kind == .text || item.kind == .link {
                    item.refreshSearchText()
                } else if item.kind == .color {
                    item.refreshColorSearchText()
                }
            }
            if item.filePathsSearchText == nil {
                item.refreshFilePathsSearchText()
            }
        }

        do {
            try context.save()
        } catch {
            logger.error("迁移后保存派生快照失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func markLegacyThumbnails(in context: ModelContext) {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.thumbnailVersion == nil && $0.thumbnailData != nil }
        )
        descriptor.propertiesToFetch = [\.id, \.thumbnailVersion]
        guard let legacy = try? context.fetch(descriptor) else {
            logger.error("迁移后读取旧缩略图失败，跳过硬编码版本")
            return
        }
        guard !legacy.isEmpty else { return }
        for item in legacy {
            item.thumbnailVersion = ClipboardItem.currentThumbnailVersion
        }
        do {
            try context.save()
        } catch {
            logger.error("迁移后保存缩略图版本失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
