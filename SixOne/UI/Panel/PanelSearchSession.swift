//
//  PanelSearchSession.swift
//  SixOne
//  搜索词到库查询的链路：输入防抖落库，Esc 清空与面板唤出立即生效。

import Foundation

final class PanelSearchSession {
    private let store: HistoryListStore
    private let searchState: SearchState
    private let navigationState: NavigationState
    private let debouncer: SearchDebouncer

    init(
        store: HistoryListStore,
        searchState: SearchState,
        navigationState: NavigationState,
        debouncer: SearchDebouncer = SearchDebouncer()
    ) {
        self.store = store
        self.searchState = searchState
        self.navigationState = navigationState
        self.debouncer = debouncer
    }

    func textDidChange() {
        deliver(searchState.text, debounced: true)
    }

    /// Esc 清空立即落库，不等防抖。
    func clear() {
        searchState.text = ""
        deliver("", debounced: false)
    }

    func syncToStore() {
        deliver(searchState.text, debounced: false)
    }

    func cancelPendingWork() {
        debouncer.cancel()
    }

    /// 查询词与当前一致时不动列表；清空后的 onChange 会再走一遍。
    private func deliver(_ raw: String, debounced: Bool) {
        debouncer.cancel()
        guard !store.matchesQuery(raw) else { return }
        // 列表随即整份换掉：只能回到顶部，选中一并摘掉。
        navigationState.selectedItemID = nil
        navigationState.isSelectionActive = false
        navigationState.requestScrollToTop()
        // 纯空白与立即入口都直接落库。
        guard debounced, !HistoryListStore.normalizedQuery(raw).isEmpty else {
            store.setSearchQuery(raw)
            return
        }
        debouncer.schedule { [weak self] in
            // 交付时输入已又变了就作废（最后一道保险）。
            guard let self, self.searchState.text == raw else { return }
            self.store.setSearchQuery(raw)
        }
    }
}
