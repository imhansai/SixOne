//
//  CollectionListStore.swift
//  SixOne
//
//  用户分组列表：后台读取，分组事件到达后重载。
//

import Foundation
import Observation
import os

@Observable
@MainActor
final class CollectionListStore {
    private let repository: ClipboardHistoryRepository
    private let eventBus: ClipboardHistoryEventBus
    private var eventObservation: ClipboardHistoryEventBus.Observation?
    private let logger = AppLog.logger("Collections")
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// 读取代号：迟到的旧结果直接丢弃，避免覆盖较新的一次加载。
    @ObservationIgnored private var loadGeneration = 0

    private(set) var groups: [CollectionRow] = []
    /// 分组名按 id 索引：列表逐行查表，避免每行扫描全部分组。
    private(set) var groupNamesByID: [UUID: String] = [:]

    init(repository: ClipboardHistoryRepository, events: ClipboardHistoryEventBus) {
        self.repository = repository
        self.eventBus = events
        eventObservation = events.observe { [weak self] event in
            guard case .collectionsChanged = event else { return }
            self?.reload()
        }
        reload()
    }

    isolated deinit {
        if let eventObservation {
            eventBus.removeObserver(eventObservation)
        }
    }

    func reload() {
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(generation: generation)
        }
    }

    private func load(generation: Int) async {
        do {
            let rows = try await repository.collections()
            guard generation == loadGeneration else { return }
            apply(rows)
        } catch {
            guard generation == loadGeneration else { return }
            logger.error("读取分组列表失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func waitForPendingLoad() async {
        await loadTask?.value
    }

    func group(id: UUID) -> CollectionRow? {
        groups.first { $0.id == id }
    }

    /// 顺序与名字索引一起更新，避免分叉。
    private func apply(_ rows: [CollectionRow]) {
        groups = rows
        groupNamesByID = Dictionary(
            rows.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
