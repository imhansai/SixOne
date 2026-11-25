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

    /// 搜索命中回到历史：记住目标与它的视口偏移再清空搜索，窗口落定后由列表选中定位。
    func clearForLocation(id: UUID, rowsAbove: Int) {
        navigationState.requestLocateInHistory(id: id, rowsAbove: rowsAbove)
        searchState.text = ""
        deliver("", debounced: false)
    }

    /// 换筛选：各区一起生效，只发一次查询。
    func filterDidChange(_ filter: HistoryFilter) {
        debouncer.cancel()
        let query = HistoryQuery(
            text: HistoryListStore.normalizedQuery(searchState.text),
            filter: filter
        )
        guard !store.matches(query) else { return }
        resetNavigationForQueryChange(preserveLocate: false)
        store.setQuery(query)
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
        let normalized = HistoryListStore.normalizedQuery(raw)
        let isLocating = normalized.isEmpty && navigationState.pendingLocate != nil
        resetNavigationForQueryChange(preserveLocate: isLocating)
        // 纯空白与立即入口都直接落库。
        guard debounced, !normalized.isEmpty else {
            store.setSearchQuery(raw)
            return
        }
        debouncer.schedule { [weak self] in
            // 交付时输入已又变了就作废（最后一道保险）。
            guard let self, self.searchState.text == raw else { return }
            self.store.setSearchQuery(raw)
        }
    }

    /// 列表整份换掉：回顶并清选中；定位清词保留目标，且不先回顶。
    private func resetNavigationForQueryChange(preserveLocate: Bool) {
        if !preserveLocate {
            navigationState.clearPendingLocate()
        }
        navigationState.selectedItemID = nil
        navigationState.isSelectionActive = false
        if !preserveLocate {
            navigationState.requestScrollToTop()
        }
    }
}
