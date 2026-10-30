//
//  ListRowVisibility.swift
//  SixOne
//
//  历史列表与文件组列表共用的完整可见行判定。
//

import AppKit

enum ListRowVisibility {
    /// 整行落在可视矩形内才算完整可见。
    static func fullyVisibleRowRange(in tableView: NSTableView) -> ClosedRange<Int>? {
        let visible = tableView.visibleRect
        let intersecting = tableView.rows(in: visible)
        guard intersecting.location != NSNotFound, intersecting.length > 0 else { return nil }
        let slack = visible.insetBy(dx: 0, dy: -ClipboardLayout.geometryTolerance)
        var first = intersecting.location
        var last = intersecting.location + intersecting.length - 1
        while first <= last, !slack.contains(tableView.rect(ofRow: first)) { first += 1 }
        while last >= first, !slack.contains(tableView.rect(ofRow: last)) { last -= 1 }
        guard first <= last else { return nil }
        return first...last
    }
}
