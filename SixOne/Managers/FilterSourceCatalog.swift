//
//  FilterSourceCatalog.swift
//  SixOne
//
//  筛选弹层的来源候选：面板每次唤出时刷新，打开弹层直接读缓存，避免首帧长高。
//

import Foundation
import Observation

@Observable
@MainActor
final class FilterSourceCatalog {
    private let store: HistoryListStore
    private(set) var bundleIdentifiers: [String] = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(store: HistoryListStore) {
        self.store = store
    }

    func reload() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            guard let identifiers = await store.sourceApplications() else { return }
            guard !Task.isCancelled, identifiers != bundleIdentifiers else { return }
            bundleIdentifiers = identifiers
        }
    }

    func waitForPendingLoad() async {
        await loadTask?.value
    }
}
