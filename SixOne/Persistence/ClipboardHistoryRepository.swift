//
//  ClipboardHistoryRepository.swift
//  SixOne
//
//  历史库只读口：读在后台 actor 执行，只把 `HistoryRow` 快照交回主线程。
//

import Foundation
import SwiftData

/// 列表行轻量快照，不含大字段；title 为 nil 时按类型显示兜底文案。
nonisolated struct HistoryRow: Identifiable, Sendable, Equatable {
    let id: UUID
    let kind: ClipboardItemKind
    let title: String?
    let filePath: String?
    let fileCount: Int
    let contentType: String?
    let thumbnailData: Data?
    /// 缩略图生成版本；nil 或旧版本会触发一次性重算。
    let thumbnailVersion: Int?
    let sourceAppBundleIdentifier: String?
    let lastActivityAt: Date
}

nonisolated extension HistoryRow {
    /// 取窗与单行刷新共用的取列清单，避免一处加列、另一处漏加。
    static var readProperties: [PartialKeyPath<ClipboardItem>] {
        [
            \.id, \.kindRaw, \.titleSnapshot, \.thumbnailData, \.thumbnailVersion,
            \.filePath, \.filePaths, \.contentType, \.sourceAppBundleIdentifier, \.lastActivityAt,
        ]
    }

    /// 从条目取快照；只读非隔离成员，任意线程可调。
    init(_ item: ClipboardItem) {
        self.init(
            id: item.id,
            kind: item.kind,
            title: item.titleSnapshot,
            filePath: item.filePath,
            fileCount: item.allFilePaths.count,
            contentType: item.contentType,
            thumbnailData: item.thumbnailData,
            thumbnailVersion: item.thumbnailVersion,
            sourceAppBundleIdentifier: item.sourceAppBundleIdentifier,
            lastActivityAt: item.lastActivityAt
        )
    }
}

nonisolated protocol ClipboardHistoryRepository: Sendable {
    /// 最近 `limit` 条行快照，按 recencyID 倒序；query 为空表示浏览全部。
    func latest(query: String, limit: Int) async throws -> [HistoryRow]

    /// 按 id 取行快照，用于触达置顶与缩略图更新后的原位刷新。
    func row(id: UUID) async throws -> HistoryRow?

    /// 条目是否还在库里，用于校验预览/选中是否失效。
    func itemExists(id: UUID) async throws -> Bool
}

/// 每次查询新建 `ModelContext`，避免旧 context 看不到新写入或读到已删除的行。
actor SwiftDataHistoryRepository: ClipboardHistoryRepository {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func latest(query: String, limit: Int) async throws -> [HistoryRow] {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.recencyID, order: .reverse)]
        )
        descriptor.predicate = query.isEmpty ? nil : Self.searchPredicate(query: query)
        descriptor.fetchLimit = limit
        descriptor.propertiesToFetch = HistoryRow.readProperties
        return try context.fetch(descriptor).map(HistoryRow.init)
    }

    func row(id: UUID) async throws -> HistoryRow? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = HistoryRow.readProperties
        return try context.fetch(descriptor).first.map(HistoryRow.init)
    }

    func itemExists(id: UUID) async throws -> Bool {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.id]
        return try !context.fetch(descriptor).isEmpty
    }

    // MARK: - 查询谓词

    /// 搜索匹配正文、标题快照与文件路径；路径列汇总了组内全部文件名。
    nonisolated private static func searchPredicate(query: String) -> Predicate<ClipboardItem> {
        #Predicate<ClipboardItem> { item in
            item.searchText?.localizedStandardContains(query) ?? false
                || item.titleSnapshot?.localizedStandardContains(query) ?? false
                || item.filePathsSearchText?.localizedStandardContains(query) ?? false
        }
    }
}
