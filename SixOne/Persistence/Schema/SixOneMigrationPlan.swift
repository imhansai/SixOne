//
//  SixOneMigrationPlan.swift
//  SixOne
//
//  历史库版本迁移：V1 → V2 只补真正缺失的派生快照；V2 → V3 新增 id 索引与缩略图版本字段；
//  V3 → V4 新增可空别名字段；V4 → V5 新增可空分组归属与分组表；
//  V5 → V6 新增分组排序位置，都交给轻量迁移。
//

import Foundation
import SwiftData
import os

nonisolated enum SixOneMigrationPlan: SchemaMigrationPlan {
    private static let logger = AppLog.logger("Migration")

    static var schemas: [any VersionedSchema.Type] {
        [
            SixOneSchemaV1.self, SixOneSchemaV2.self, SixOneSchemaV3.self,
            SixOneSchemaV4.self, SixOneSchemaV5.self, SixOneSchemaV6.self,
        ]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6]
    }

    /// 结构迁移由 SwiftData 完成；这里只补旧条目真正缺失的派生快照。
    /// 健康数据（快照齐全）不做任何逐行写入，避免大库首启被 5 万次更新拖住。
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SixOneSchemaV1.self,
        toVersion: SixOneSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            backfillMissingSnapshots(in: context)
        }
    )

    /// V3 只加索引与可空字段，交给轻量迁移；旧缩略图版本保持 nil，由列表惰性重算。
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SixOneSchemaV2.self,
        toVersion: SixOneSchemaV3.self
    )

    /// V4 只加可空别名，旧条目保持 nil，不需要逐行回填。
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SixOneSchemaV3.self,
        toVersion: SixOneSchemaV4.self
    )

    /// V5 只加可空分组归属和空分组表，旧条目保持未分组。
    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: SixOneSchemaV4.self,
        toVersion: SixOneSchemaV5.self
    )

    /// V6 只加带默认值的排序位置，旧分组合为同一位置。
    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: SixOneSchemaV5.self,
        toVersion: SixOneSchemaV6.self
    )

    private static func backfillMissingSnapshots(in context: ModelContext) {
        // 这一阶段的目标库还是 V2，必须显式取 V2 模型，不能用当前版本的类型别名。
        var changed = false
        changed = backfillContentKeys(in: context) || changed
        changed = backfillSearchTexts(in: context) || changed
        changed = backfillFilePaths(in: context) || changed
        guard changed else { return }

        do {
            try context.save()
        } catch {
            logger.error("迁移后保存派生快照失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func backfillContentKeys(in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<SixOneSchemaV2.ClipboardItem>(
            predicate: #Predicate { $0.contentKeySnapshot == nil }
        )
        descriptor.propertiesToFetch = [
            \.id, \.kindRaw, \.text, \.imageData, \.filePath, \.filePaths,
            \.colorData, \.contentKeySnapshot, \.contentKeyVersion,
        ]
        guard let items = try? context.fetch(descriptor), !items.isEmpty else { return false }
        for item in items {
            item.refreshContentKey()
        }
        logger.notice("迁移补齐 \(items.count, privacy: .public) 条旧条目的去重快照")
        return true
    }

    private static func backfillSearchTexts(in context: ModelContext) -> Bool {
        // 文件/图片本来就没有 searchText，先按类型过滤，避免把健康数据也逐行写一遍。
        var descriptor = FetchDescriptor<SixOneSchemaV2.ClipboardItem>(
            predicate: #Predicate { $0.searchText == nil }
        )
        descriptor.propertiesToFetch = [\.id, \.kindRaw, \.text, \.colorData, \.searchText]
        guard let items = try? context.fetch(descriptor), !items.isEmpty else { return false }

        var changed = 0
        for item in items {
            let before = item.searchText
            if item.kind == .text || item.kind == .link {
                item.refreshSearchText()
            } else if item.kind == .color {
                item.refreshColorSearchText()
            } else {
                continue
            }
            if item.searchText != before { changed += 1 }
        }
        guard changed > 0 else { return false }
        logger.notice("迁移补齐 \(changed, privacy: .public) 条旧条目的搜索快照")
        return true
    }

    private static func backfillFilePaths(in context: ModelContext) -> Bool {
        // 只有带路径的条目才需要路径快照；文本条目继续留 nil。
        var descriptor = FetchDescriptor<SixOneSchemaV2.ClipboardItem>(
            predicate: #Predicate { $0.filePathsSearchText == nil && $0.filePath != nil }
        )
        descriptor.propertiesToFetch = [\.id, \.filePath, \.filePaths, \.filePathsSearchText]
        guard let items = try? context.fetch(descriptor), !items.isEmpty else { return false }
        for item in items {
            item.refreshFilePathsSearchText()
        }
        logger.notice("迁移补齐 \(items.count, privacy: .public) 条旧条目的路径快照")
        return true
    }
}
