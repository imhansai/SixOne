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

    /// 单条是否仍命中查询；搜索/筛选变更时避免整窗重查。
    func rowMatches(id: UUID, query: HistoryQuery) async throws -> Bool

    /// 条目是否还在库里，用于校验预览/选中是否失效。
    func itemExists(id: UUID) async throws -> Bool

    /// 用户分组列表；按用户排序，旧数据按名称本地化兜底。
    func collections() async throws -> [CollectionRow]

    /// 最近窗口里出现过的来源 App；按最近出现排序、去重，筛选弹层的「来源」区用。
    func sourceApplications(limit: Int) async throws -> [String]
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
            \.id, \.kindRaw, \.collectionID, \.sourceAppBundleIdentifier, \.lastActivityAt,
            \.searchText, \.titleSnapshot, \.alias, \.filePathsSearchText,
        ]
        guard let item = try context.fetch(descriptor).first else { return false }

        guard query.filter.matches(
            kind: item.kind,
            collectionID: item.collectionID,
            sourceAppBundleIdentifier: item.sourceAppBundleIdentifier,
            lastActivityAt: item.lastActivityAt
        ) else { return false }

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
        descriptor.propertiesToFetch = [\.id, \.name, \.createdAt, \.sortOrder]
        return try context.fetch(descriptor)
            .map(CollectionRow.init)
            .sorted(by: CollectionRow.displayOrder)
    }

    func sourceApplications(limit: Int) async throws -> [String] {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.recencyID, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.propertiesToFetch = [\.sourceAppBundleIdentifier]
        var seen: Set<String> = []
        var result: [String] = []
        for item in try context.fetch(descriptor) {
            guard let bundleID = item.sourceAppBundleIdentifier,
                  !bundleID.isEmpty,
                  seen.insert(bundleID).inserted
            else { continue }
            result.append(bundleID)
        }
        return result
    }

    // MARK: - 查询谓词

    /// 每个维度单独成谓词再合取；单条表达式过长会拖垮类型检查，也方便独立测试。
    nonisolated private static func searchPredicate(
        query: HistoryQuery,
        olderThan cursor: UUID? = nil
    ) -> Predicate<ClipboardItem>? {
        let text = query.text
        let filter = query.filter
        var predicates: [Predicate<ClipboardItem>] = []

        if let cursor {
            predicates.append(#Predicate { $0.recencyID < cursor })
        }
        if !filter.collections.isEmpty {
            let collectionPredicates = filter.collections
                .sorted { $0.uuidString < $1.uuidString }
                .map { collectionID in
                    #Predicate<ClipboardItem> { $0.collectionID == collectionID }
                }
            predicates.append(Predicate(any: collectionPredicates))
        }
        if !text.isEmpty {
            predicates.append(#Predicate { item in
                (item.searchText?.localizedStandardContains(text) ?? false)
                    || (item.titleSnapshot?.localizedStandardContains(text) ?? false)
                    || (item.alias?.localizedStandardContains(text) ?? false)
                    || (item.filePathsSearchText?.localizedStandardContains(text) ?? false)
            })
        }
        if !filter.kinds.isEmpty {
            let kinds = filter.kinds.map(\.rawValue).sorted()
            predicates.append(#Predicate { kinds.contains($0.kindRaw) })
        }
        if !filter.sourceApps.isEmpty {
            // CoreData 不支持对可空列做 IN / nil 合并；逐来源等值再取并集。
            let sourcePredicates = filter.sourceApps.sorted().map { source in
                #Predicate<ClipboardItem> { $0.sourceAppBundleIdentifier == source }
            }
            predicates.append(Predicate(any: sourcePredicates))
        }
        if !filter.dateRanges.isEmpty {
            let datePredicates = filter.dateRanges.map { range -> Predicate<ClipboardItem> in
                let bounds = range.bounds()
                let start = bounds.start
                let end = bounds.end
                return #Predicate { $0.lastActivityAt >= start && $0.lastActivityAt < end }
            }
            predicates.append(Predicate(any: datePredicates))
        }

        guard !predicates.isEmpty else { return nil }
        return Predicate(all: predicates)
    }
}
