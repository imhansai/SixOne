//
//
//  SelectionMirror.swift
//  SixOne
//  模型选中到表格的单向镜像。
//

import AppKit

/// 单向同步，表格不回写。
@MainActor
struct SelectionMirror<ID: Hashable> {
    private var mirroredID: ID?

    mutating func reset() {
        mirroredID = nil
    }

    mutating func sync(
        _ id: ID?,
        in tableView: NSTableView,
        rowIndex: (ID) -> Int?
    ) {
        guard let id else {
            guard mirroredID != nil else { return }
            mirroredID = nil
            tableView.deselectAll(nil)
            return
        }
        guard mirroredID != id, let index = rowIndex(id) else { return }
        mirroredID = id
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
}
