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
}

nonisolated extension CollectionRow {
    init(_ collection: ClipboardCollection) {
        self.init(id: collection.id, name: collection.name, createdAt: collection.createdAt)
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

nonisolated enum CollectionMutationFailure: Error, Equatable {
    case emptyName
    case duplicateName
    case notFound
    case persistence
}
