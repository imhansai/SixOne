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
    /// 排序键；补位查询以它为游标。
    let recencyID: UUID
    let kind: ClipboardItemKind
    let title: String?
    /// 非空时替换列表标题。
    let alias: String?
    let filePath: String?
    let fileCount: Int
    let contentType: String?
    let thumbnailData: Data?
    /// 缩略图生成版本；nil 或旧版本会触发一次性重算。
    let thumbnailVersion: Int?
    let sourceAppBundleIdentifier: String?
    let lastActivityAt: Date
    /// 分组归属；nil 表示未分组。列表筛选与行菜单使用。
    let collectionID: UUID?

    init(
        id: UUID,
        recencyID: UUID,
        kind: ClipboardItemKind,
        title: String?,
        alias: String?,
        filePath: String?,
        fileCount: Int,
        contentType: String?,
        thumbnailData: Data?,
        thumbnailVersion: Int?,
        sourceAppBundleIdentifier: String?,
        lastActivityAt: Date,
        collectionID: UUID? = nil
    ) {
        self.id = id
        self.recencyID = recencyID
        self.kind = kind
        self.title = title
        self.alias = alias
        self.filePath = filePath
        self.fileCount = fileCount
        self.contentType = contentType
        self.thumbnailData = thumbnailData
        self.thumbnailVersion = thumbnailVersion
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.lastActivityAt = lastActivityAt
        self.collectionID = collectionID
    }
}

nonisolated extension HistoryRow {
    /// 取窗与单行刷新共用的取列清单，避免一处加列、另一处漏加。
    static var readProperties: [PartialKeyPath<ClipboardItem>] {
        [
            \.id, \.recencyID, \.kindRaw, \.titleSnapshot, \.alias, \.thumbnailData, \.thumbnailVersion,
            \.filePath, \.filePaths, \.contentType, \.sourceAppBundleIdentifier, \.lastActivityAt,
            \.collectionID,
        ]
    }

    /// 从条目取快照；只读非隔离成员，任意线程可调。
    init(_ item: ClipboardItem) {
        self.init(
            id: item.id,
            recencyID: item.recencyID,
            kind: item.kind,
            title: item.titleSnapshot,
            alias: item.alias,
            filePath: item.filePath,
            fileCount: item.allFilePaths.count,
            contentType: item.contentType,
            thumbnailData: item.thumbnailData,
            thumbnailVersion: item.thumbnailVersion,
            sourceAppBundleIdentifier: item.sourceAppBundleIdentifier,
            lastActivityAt: item.lastActivityAt,
            collectionID: item.collectionID
        )
    }
}

nonisolated protocol ClipboardHistoryRepository: Sendable {
    /// 最近 `limit` 条行快照，按 recencyID 倒序；query 为空表示浏览全部。
    func latest(query: HistoryQuery, limit: Int) async throws -> [HistoryRow]

    /// 比 `cursor` 更旧的 `limit` 条；删除补位用，走 recencyID 索引。
    func rows(after cursor: UUID, query: HistoryQuery, limit: Int) async throws -> [HistoryRow]

    /// 按 id 取行快照，用于触达置顶与缩略图更新后的原位刷新。
    func row(id: UUID) async throws -> HistoryRow?

    /// 单条是否仍命中查询；搜索/分组变更时避免整窗重查。
    func rowMatches(id: UUID, query: HistoryQuery) async throws -> Bool

    /// 条目是否还在库里，用于校验预览/选中是否失效。
    func itemExists(id: UUID) async throws -> Bool

    /// 用户分组列表；按名称本地化排序。
    func collections() async throws -> [CollectionRow]
}

/// 每次查询新建 `ModelContext`，避免旧 context 看不到新写入或读到已删除的行。
actor SwiftDataHistoryRepository: ClipboardHistoryRepository {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func latest(query: HistoryQuery, limit: Int) async throws -> [HistoryRow] {
        try fetch(query: query, after: nil, limit: limit)
    }

    func rows(after cursor: UUID, query: HistoryQuery, limit: Int) async throws -> [HistoryRow] {
        try fetch(query: query, after: cursor, limit: limit)
    }

    private func fetch(query: HistoryQuery, after cursor: UUID?, limit: Int) throws -> [HistoryRow] {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.recencyID, order: .reverse)]
        )
        descriptor.predicate = Self.searchPredicate(query: query, olderThan: cursor)
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

    /// 与 `searchPredicate` 保持一致，只查这一条。
    func rowMatches(id: UUID, query: HistoryQuery) async throws -> Bool {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [
            \.id, \.collectionID, \.searchText, \.titleSnapshot, \.alias, \.filePathsSearchText,
        ]
        guard let item = try context.fetch(descriptor).first else { return false }

        switch query.collection {
        case .all:
            break
        case .ungrouped:
            guard item.collectionID == nil else { return false }
        case .collection(let collectionID):
            guard item.collectionID == collectionID else { return false }
        }

        guard !query.text.isEmpty else { return true }
        let text = query.text
        return (item.searchText?.localizedStandardContains(text) ?? false)
            || (item.titleSnapshot?.localizedStandardContains(text) ?? false)
            || (item.alias?.localizedStandardContains(text) ?? false)
            || (item.filePathsSearchText?.localizedStandardContains(text) ?? false)
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

    func collections() async throws -> [CollectionRow] {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardCollection>()
        descriptor.propertiesToFetch = [\.id, \.name, \.createdAt]
        let rows = try context.fetch(descriptor).map(CollectionRow.init)
        return rows.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            if order == .orderedSame { return $0.createdAt < $1.createdAt }
            return order == .orderedAscending
        }
    }

    // MARK: - 查询谓词

    /// 分组条件与搜索共用同一次扫描；`olderThan` 为补位游标。
    nonisolated private static func searchPredicate(
        query: HistoryQuery,
        olderThan cursor: UUID? = nil
    ) -> Predicate<ClipboardItem>? {
        let text = query.text

        if let cursor {
            switch query.collection {
            case .all:
                if text.isEmpty { return #Predicate { $0.recencyID < cursor } }
                return #Predicate { item in
                    item.recencyID < cursor
                        && ((item.searchText?.localizedStandardContains(text) ?? false)
                            || (item.titleSnapshot?.localizedStandardContains(text) ?? false)
                            || (item.alias?.localizedStandardContains(text) ?? false)
                            || (item.filePathsSearchText?.localizedStandardContains(text) ?? false))
                }
            case .ungrouped:
                if text.isEmpty {
                    return #Predicate { $0.recencyID < cursor && $0.collectionID == nil }
                }
                return #Predicate { item in
                    item.recencyID < cursor
                        && item.collectionID == nil
                        && ((item.searchText?.localizedStandardContains(text) ?? false)
                            || (item.titleSnapshot?.localizedStandardContains(text) ?? false)
                            || (item.alias?.localizedStandardContains(text) ?? false)
                            || (item.filePathsSearchText?.localizedStandardContains(text) ?? false))
                }
            case .collection(let collectionID):
                if text.isEmpty {
                    return #Predicate {
                        $0.recencyID < cursor && $0.collectionID == collectionID
                    }
                }
                return #Predicate { item in
                    item.recencyID < cursor
                        && item.collectionID == collectionID
                        && ((item.searchText?.localizedStandardContains(text) ?? false)
                            || (item.titleSnapshot?.localizedStandardContains(text) ?? false)
                            || (item.alias?.localizedStandardContains(text) ?? false)
                            || (item.filePathsSearchText?.localizedStandardContains(text) ?? false))
                }
            }
        }

        switch query.collection {
        case .all:
            guard !text.isEmpty else { return nil }
            return #Predicate { item in
                (item.searchText?.localizedStandardContains(text) ?? false)
                    || (item.titleSnapshot?.localizedStandardContains(text) ?? false)
                    || (item.alias?.localizedStandardContains(text) ?? false)
                    || (item.filePathsSearchText?.localizedStandardContains(text) ?? false)
            }
        case .ungrouped:
            if text.isEmpty { return #Predicate { $0.collectionID == nil } }
            return #Predicate { item in
                item.collectionID == nil
                    && ((item.searchText?.localizedStandardContains(text) ?? false)
                        || (item.titleSnapshot?.localizedStandardContains(text) ?? false)
                        || (item.alias?.localizedStandardContains(text) ?? false)
                        || (item.filePathsSearchText?.localizedStandardContains(text) ?? false))
            }
        case .collection(let collectionID):
            if text.isEmpty { return #Predicate { $0.collectionID == collectionID } }
            return #Predicate { item in
                item.collectionID == collectionID
                    && ((item.searchText?.localizedStandardContains(text) ?? false)
                        || (item.titleSnapshot?.localizedStandardContains(text) ?? false)
                        || (item.alias?.localizedStandardContains(text) ?? false)
                        || (item.filePathsSearchText?.localizedStandardContains(text) ?? false))
            }
        }
    }
}
