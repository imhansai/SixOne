//
//  SelectionMirror.swift
//  SixOne
//  模型选中到 NSTableView 的单向镜像。
//

import AppKit

/// 把模型选中单向同步到表格；表格不改写模型。
@MainActor
struct SelectionMirror<ID: Hashable> {
    private var mirroredID: ID?

    mutating func reset() {
        mirroredID = nil
    }

    /// 返回是否真的操作了表格选中。
    @discardableResult
    mutating func sync(
        _ id: ID?,
        in tableView: NSTableView,
        rowIndex: (ID) -> Int?
    ) -> Bool {
        guard let id else {
            guard mirroredID != nil else { return false }
            mirroredID = nil
            tableView.deselectAll(nil)
            return true
        }
        guard mirroredID != id, let index = rowIndex(id) else { return false }
        mirroredID = id
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        return true
    }
}
