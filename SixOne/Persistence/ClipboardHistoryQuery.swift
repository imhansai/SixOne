//
//  ClipboardHistoryQuery.swift
//  SixOne
//
//  历史读取条件：搜索词 + 分组筛选；值类型便于列表比较迟到结果。
//

import Foundation

nonisolated enum CollectionFilter: Hashable, Sendable {
    case all
    case ungrouped
    case collection(UUID)
}

nonisolated struct HistoryQuery: Hashable, Sendable {
    var text: String
    var collection: CollectionFilter

    init(text: String = "", collection: CollectionFilter = .all) {
        self.text = text
        self.collection = collection
    }
}
