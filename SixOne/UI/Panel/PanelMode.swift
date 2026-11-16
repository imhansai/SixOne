//
//  PanelMode.swift
//  SixOne
//  面板导航层级；编辑、搜索与筛选焦点是正交状态。
//

import Foundation

enum PanelMode: Equatable {
    case historyList
    case itemPreview(id: UUID)
    case groupOverview(itemID: UUID)
    case groupFile(itemID: UUID, index: Int)
}

extension PanelMode {
    /// 由条目与组内下标派生层级；视图与状态共用同一判定。
    static func resolve(item: ClipboardItem?, groupFileIndex: Int?) -> PanelMode {
        guard let item else { return .historyList }
        guard item.kind == .file, item.fileCount > 1 else { return .itemPreview(id: item.id) }
        if let groupFileIndex { return .groupFile(itemID: item.id, index: groupFileIndex) }
        return .groupOverview(itemID: item.id)
    }

    var isPreviewing: Bool { self != .historyList }

    var isGroupOverview: Bool {
        if case .groupOverview = self { return true }
        return false
    }

    var isGroupFile: Bool {
        if case .groupFile = self { return true }
        return false
    }

    var isGroupPreview: Bool { isGroupOverview || isGroupFile }
}

extension PreviewState {
    /// 当前导航层级；编辑、搜索与筛选焦点不在此列。
    var mode: PanelMode {
        .resolve(item: presentation.item, groupFileIndex: group.fileIndex)
    }
}
