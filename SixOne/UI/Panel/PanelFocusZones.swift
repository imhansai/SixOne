//
//  PanelFocusZones.swift
//  SixOne
//  面板内的 Tab 循环：搜索框 ↔ 筛选 ↔ 更多操作 ↔ 列表。

import AppKit

final class PanelFocusZones {
    private let panel: ClipboardPanel
    private let searchState: SearchState
    private let moreActionsState: MoreActionsState
    private let filterState: FilterState
    private let navigationState: NavigationState
    private let cursor: PanelSelectionCursor
    private let isFullKeyboardAccessEnabled: () -> Bool

    init(
        panel: ClipboardPanel,
        searchState: SearchState,
        moreActionsState: MoreActionsState,
        filterState: FilterState,
        navigationState: NavigationState,
        cursor: PanelSelectionCursor,
        isFullKeyboardAccessEnabled: @escaping () -> Bool
    ) {
        self.panel = panel
        self.searchState = searchState
        self.moreActionsState = moreActionsState
        self.filterState = filterState
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
            focusFilter()
        case (.search, false, false):
            focusList()
        case (.filter, true, _):
            focusSearch()
        case (.filter, false, true):
            focusMoreActions()
        case (.filter, false, false):
            focusList()
        case (.moreActions, true, true):
            focusFilter()
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
        filterState.resignFocus()
        filterState.dismiss()
        navigationState.isSelectionActive = false
        searchState.focusRequestID += 1
    }

    /// 进入筛选站；开合由按钮自己的 Space / Return 完成。
    func focusFilter() {
        searchState.resignFocus()
        moreActionsState.resignFocus()
        navigationState.isSelectionActive = false
        // 同步置位，连续 Tab 时 current 立刻正确。
        filterState.isFocused = true
        filterState.focusRequestID += 1
    }

    func focusMoreActions() {
        searchState.resignFocus()
        filterState.resignFocus()
        filterState.dismiss()
        navigationState.isSelectionActive = false
        // 同步置位，连续 Tab 时 current 立刻正确。
        moreActionsState.isFocused = true
        moreActionsState.focusRequestID += 1
    }

    /// 进入列表站：解除控件焦点，无选中时落到第一条。
    func focusList() {
        searchState.resignFocus()
        moreActionsState.resignFocus()
        filterState.resignFocus()
        filterState.dismiss()
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
        case filter
        case moreActions
        case list
    }

    private var current: Zone {
        if filterState.isFocused { return .filter }
        if moreActionsState.isFocused { return .moreActions }
        if searchState.isFocused { return .search }
        return .list
    }
}
