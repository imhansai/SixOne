//
//  SixOneMigrationPlan.swift
//  SixOne
//
//  历史库版本迁移：V1 → V2 新增去重 key 版本字段，并补齐旧条目缺失的派生快照。
//

import Foundation
import SwiftData
import os

nonisolated enum SixOneMigrationPlan: SchemaMigrationPlan {
    private static let logger = AppLog.logger("Migration")

    static var schemas: [any VersionedSchema.Type] {
        [SixOneSchemaV1.self, SixOneSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// 结构迁移由 SwiftData 完成；这里只补数据。
    /// 补齐失败不回滚迁移：结构已经可用，派生快照缺失由读取路径兜底。
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SixOneSchemaV1.self,
        toVersion: SixOneSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            backfillDerivedSnapshots(in: context)
        }
    )

    private static func backfillDerivedSnapshots(in context: ModelContext) {
        // V1 没有版本字段，迁移后这些行必然为 nil；只取它们，避免全表扫描。
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { item in
                item.contentKeyVersion == nil
            }
        )
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
                item.contentKeyVersion = ClipboardItem.currentContentKeyVersion
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
}
