//
//  PanelSession.swift
//  SixOne

import Foundation

struct PanelSession {
    /// 收起时正在看的预览条目 id（可能已被裁剪，唤出时要校验）。
    var previewItemID: UUID?
    var selectedItemID: UUID?
    /// 滚动锚点用 id 而非行号，因为列表可能已被刷新。
    var topVisibleRowID: UUID?
    /// 可见区首行号，决定唤出时要不要重载最近一窗。
    var topVisibleIndex: Int
    var isSelectionActive: Bool

    var isDeepScroll: Bool { topVisibleIndex > ClipboardLayout.viewportRowCount }

    /// 与当前行对照后的恢复结果；纯计算，副作用留给调用方。
    /// 收起期间来过新复制就放弃旧位置：用户要看的是新顶部，不是上次停下的地方。
    func resolve(againstRows rows: [HistoryRow], hasNewContent: Bool) -> Resolution {
        guard !hasNewContent else {
            return Resolution(selectedItemID: nil, isSelectionActive: false, scrollTarget: .top)
        }
        let loadedIDs = Set(rows.map(\.id))
        // 条目可能已被裁剪 / 清空，不在就回落为没有选中。
        let selected = selectedItemID.flatMap { loadedIDs.contains($0) ? $0 : nil }
        return Resolution(
            selectedItemID: selected,
            isSelectionActive: selected == nil ? false : isSelectionActive,
            scrollTarget: topVisibleRowID.flatMap { loadedIDs.contains($0) ? .row($0) : nil }
        )
    }

    struct Resolution: Equatable {
        let selectedItemID: UUID?
        let isSelectionActive: Bool
        let scrollTarget: HistoryListScrollTarget?
    }
}
