//
//  ClipboardHistoryQuery.swift
//  SixOne
//
//  历史读取条件：搜索词 + 分组筛选；值类型便于列表比较迟到结果。
//

import Foundation

nonisolated enum CollectionFilter: Hashable, Sendable {
    /// 不筛选：全部条目（含未分组）。
    case all
    case collection(UUID)
}

nonisolated extension CollectionFilter {
    /// 点分组 chip：未选中则只看该组，已选中则取消筛选、回到全部数据。
    func toggled(_ collectionID: UUID) -> CollectionFilter {
        self == .collection(collectionID) ? .all : .collection(collectionID)
    }

    /// 收起期间有新复制：唤出时放弃分组筛选，保证新条目可见；否则保留上次筛选。
    func restoredOnShow(hasNewContent: Bool) -> CollectionFilter {
        hasNewContent ? .all : self
    }
}

nonisolated struct HistoryQuery: Hashable, Sendable {
    var text: String
    var collection: CollectionFilter

    init(text: String = "", collection: CollectionFilter = .all) {
        self.text = text
        self.collection = collection
    }
}
