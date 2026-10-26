//
//  HistoryListStore.swift
//  SixOne
//
//  列表的数据源与刷新策略；读库在后台，主线程只换数组并通知视图。
//

import Foundation
import Observation
import os

/// 历史列表数据源：只取最近一窗行（浏览与搜索共用上限），更早的靠搜索回溯。
@Observable
final class HistoryListStore {
    private let repository: ClipboardHistoryRepository
    private let logger = AppLog.logger("HistoryList")
    let windowLimit = 1000
    private(set) var rows: [HistoryRow] = []
    private(set) var hasOlder = false
    private(set) var isLoading = false
    /// 最近一次加载是否失败；失败时保留旧 rows，文案由视图层给。
    private(set) var didFailToLoad = false
    private(set) var dataRevision = 0
    private var topVisibleIndex = 0
    private var needsTopRefresh = false
    /// 列表是否在屏幕上；收起后不再攒刷新，避免唤出时与 ⌘↑ 抢时序。
    private var isListVisible = true
    private(set) var query = ""
    var isSearching: Bool { !query.isEmpty }
    private var generation = 0
    private var loadTask: Task<Void, Never>?

    init(repository: ClipboardHistoryRepository, events: ClipboardHistoryEventBus) {
        self.repository = repository
        // 推迟一轮主线程再处理，避免读到发布方的写库中间状态。
        events.observe { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    // MARK: - 窗口加载

    func setSearchQuery(_ raw: String) {
        let normalized = Self.normalizedQuery(raw)
        guard normalized != query else { return }
        query = normalized
        startWindowLoad()
    }

    /// 搜索词归一化：只把换行类字符转为空格，与 searchText 快照一致。
    static func normalizedQuery(_ raw: String) -> String {
        ClipboardItem.normalizedSearchText(raw) ?? ""
    }

    func matchesQuery(_ raw: String) -> Bool {
        Self.normalizedQuery(raw) == query
    }

    /// 重置并加载最近一窗；已在加载中则跳过。
    func loadLatest() {
        guard !isLoading else { return }
        startWindowLoad()
    }

    func loadLatestAndWait() async {
        startWindowLoad()
        await waitForPendingLoad()
    }

    private func startWindowLoad() {
        generation &+= 1
        let generation = self.generation
        let query = self.query
        isLoading = true
        needsTopRefresh = false
        // 不把 hasOlder 置回 false：随新结果一起更新，免得视口挤动。
        loadTask = Task { [weak self] in
            guard let self else { return }
            let window = await self.fetchWindow(query: query)
            guard generation == self.generation else { return }
            self.isLoading = false
            guard let window else {
                self.didFailToLoad = true
                return
            }
            self.didFailToLoad = false
            self.rows = window.rows
            self.hasOlder = window.hasOlder
            self.dataRevision &+= 1
        }
    }

    func waitForPendingLoad() async {
        await loadTask?.value
    }

    /// 记录视口顶行；深处攒下的刷新回到顶部再执行。
    func noteTopVisibleIndex(_ index: Int) {
        topVisibleIndex = max(0, index)
        if rows.isEmpty {
            loadLatest()
            return
        }
        if needsTopRefresh, topVisibleIndex == 0 {
            loadLatest()
        }
    }

    func setListVisible(_ visible: Bool) {
        guard isListVisible != visible else { return }
        isListVisible = visible
        // 收起时补上攒下的刷新，不必等回到顶部。
        if !visible, needsTopRefresh { loadLatest() }
    }

    private func fetchWindow(query: String) async -> (rows: [HistoryRow], hasOlder: Bool)? {
        do {
            let fetched = try await repository.latest(query: query, limit: windowLimit + 1)
            let hasOlder = fetched.count > windowLimit
            return (Array(fetched.prefix(windowLimit)), hasOlder)
        } catch {
            logger.error("读取历史失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - 触达置顶

    private func fetchRow(id: UUID) async -> HistoryRow? {
        do {
            return try await repository.row(id: id)
        } catch {
            logger.error("读取条目快照失败（\(id.uuidString, privacy: .public)）：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func moveRowToTop(id: UUID) async {
        guard !rows.isEmpty, rows.contains(where: { $0.id == id }) else { return }
        guard let refreshed = await fetchRow(id: id) else { return }
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        var updated = rows
        updated.remove(at: index)
        updated.insert(refreshed, at: 0)
        rows = updated
        dataRevision &+= 1
    }

    private func reloadRow(id: UUID) async {
        guard !rows.isEmpty, let index = rows.firstIndex(where: { $0.id == id }) else { return }
        guard let refreshed = await fetchRow(id: id) else { return }
        rows[index] = refreshed
        dataRevision &+= 1
    }

    private func removeRow(id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows.remove(at: index)
        dataRevision &+= 1
    }

    /// 条目是否还在库里；读库出错按「还在」处理。
    func itemExists(id: UUID) async -> Bool {
        do {
            return try await repository.itemExists(id: id)
        } catch {
            return true
        }
    }

    // MARK: - 数据变化响应

    private func handle(_ event: ClipboardHistoryEvent) {
        switch event {
        case .inserted, .trimmed:
            // 停在顶部或列表不可见时立即重载；只有用户正看着深处才攒刷新。
            if topVisibleIndex <= ClipboardLayout.viewportRowCount || !isListVisible {
                startWindowLoad()
            } else {
                needsTopRefresh = true
            }
        case .cleared:
            // 条目清空：与滚动位置无关地立即清空，视口锚点归零，否则后续拷贝会被误判为滚到深处。
            topVisibleIndex = 0
            rows = []
            hasOlder = false
            isLoading = false
            dataRevision &+= 1
            startWindowLoad()
        case .touched(let id):
            if isSearching {
                startWindowLoad()
            } else {
                Task { [weak self] in await self?.moveRowToTop(id: id) }
            }
        case .thumbnailUpdated(let id):
            Task { [weak self] in await self?.reloadRow(id: id) }
        case .deleted(let id):
            removeRow(id: id)
        }
    }
}
