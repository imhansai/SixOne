//
//  PanelFocusZones.swift
//  SixOne
//  面板内的 Tab 循环：搜索框 ↔ 更多操作 ↔ 列表。

import AppKit

final class PanelFocusZones {
    private let panel: ClipboardPanel
    private let searchState: SearchState
    private let moreActionsState: MoreActionsState
    private let navigationState: NavigationState
    private let cursor: PanelSelectionCursor
    private let isFullKeyboardAccessEnabled: () -> Bool

    init(
        panel: ClipboardPanel,
        searchState: SearchState,
        moreActionsState: MoreActionsState,
        navigationState: NavigationState,
        cursor: PanelSelectionCursor,
        isFullKeyboardAccessEnabled: @escaping () -> Bool
    ) {
        self.panel = panel
        self.searchState = searchState
        self.moreActionsState = moreActionsState
        self.navigationState = navigationState
        self.cursor = cursor
        self.isFullKeyboardAccessEnabled = isFullKeyboardAccessEnabled
    }

    /// Tab 前进一格；Shift+Tab 后退一格。
    func cycle(backwards: Bool) {
        switch (current, backwards, isFullKeyboardAccessEnabled()) {
        case (.search, true, _):
            focusList()
        case (.search, false, true):
            focusMoreActions()
        case (.search, false, false):
            focusList()
        case (.moreActions, true, true):
            focusSearch()
        case (.moreActions, false, true):
            focusList()
        case (.moreActions, true, false):
            focusSearch()
        case (.moreActions, false, false):
            focusList()
        case (.list, true, true):
            focusMoreActions()
        case (.list, true, false):
            focusSearch()
        case (.list, false, _):
            focusSearch()
        }
    }

    /// 进入搜索站：保留列表选中但置灰，与 macOS 一致。
    func focusSearch() {
        moreActionsState.resignFocus()
        navigationState.isSelectionActive = false
        searchState.focusRequestID += 1
    }

    func focusMoreActions() {
        searchState.resignFocus()
        navigationState.isSelectionActive = false
        // 同步置位，连续 Tab 时 current 立刻正确。
        moreActionsState.isFocused = true
        moreActionsState.focusRequestID += 1
    }

    /// 进入列表站：解除控件焦点，无选中时落到第一条。
    func focusList() {
        searchState.resignFocus()
        moreActionsState.resignFocus()
        panel.makeFirstResponder(panel.contentView)
        if let selectedID = cursor.selectedItemID {
            navigationState.selectedItemID = selectedID
            navigationState.isSelectionActive = true
        } else {
            cursor.move(to: 0)
        }
    }

    private enum Zone {
        case search
        case moreActions
        case list
    }

    private var current: Zone {
        if moreActionsState.isFocused { return .moreActions }
        if searchState.isFocused { return .search }
        return .list
    }
}
