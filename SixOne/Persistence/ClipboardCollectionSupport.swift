//
//  ClipboardCollectionSupport.swift
//  SixOne
//
//  用户分组的数据层值：行快照、名称归一化与写入失败类型。
//

import Foundation

nonisolated struct CollectionRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    /// 用户排序位置；旧库分组同为 0。
    let sortOrder: Int

    init(id: UUID, name: String, createdAt: Date, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}

/// 行副标题上的分组标记：只在「全部」视图显示，避免分组视图里每行重复同一个名字。
nonisolated enum RowCollectionMarker {
    static func name(
        for row: HistoryRow,
        isGroupFiltered: Bool,
        groupNames: [UUID: String]
    ) -> String? {
        guard !isGroupFiltered, let collectionID = row.collectionID else { return nil }
        return groupNames[collectionID]
    }
}

nonisolated extension CollectionRow {
    init(_ collection: ClipboardCollection) {
        self.init(
            id: collection.id,
            name: collection.name,
            createdAt: collection.createdAt,
            sortOrder: collection.sortOrder
        )
    }

    /// 显示顺序：用户排序优先，位置相同时按名称与创建时间兜底。
    static func displayOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        let order = lhs.name.localizedStandardCompare(rhs.name)
        if order == .orderedSame { return lhs.createdAt < rhs.createdAt }
        return order == .orderedAscending
    }
}

nonisolated enum CollectionNameNormalizer {
    /// 分组名长度上限；弹窗与写入共用。
    static let maxLength = 40

    /// 空白折叠为单个空格、去掉首尾，超长截断；只有不可见字符视为空名。
    static func normalized(_ raw: String?) -> String? {
        VisibleNameNormalizer.normalized(raw, maxLength: maxLength)
    }
}

/// 分组名校验结果：弹窗与写入共用规则。
nonisolated enum CollectionNameValidation: Equatable {
    case empty
    case duplicate
    case valid(String)

    var canSubmit: Bool {
        if case .valid = self { return true }
        return false
    }
}

nonisolated enum CollectionNameRules {
    /// 名称比较忽略大小写。
    static func isDuplicate(_ name: String, among names: [String]) -> Bool {
        names.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// 归一化后非空且不重名才算可用。
    static func validate(
        _ raw: String?,
        among existingNames: [String]
    ) -> CollectionNameValidation {
        guard let name = CollectionNameNormalizer.normalized(raw) else { return .empty }
        return isDuplicate(name, among: existingNames) ? .duplicate : .valid(name)
    }
}

nonisolated enum CollectionMutationFailure: Error, Equatable {
    case emptyName
    case duplicateName
    case notFound
    case persistence
}
