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

    private(set) var groups: [CollectionRow] = []

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
        loadTask = Task { [weak self] in
            await self?.load()
        }
    }

    func load() async {
        do {
            groups = try await repository.collections()
        } catch {
            logger.error("读取分组列表失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func waitForPendingLoad() async {
        await loadTask?.value
    }

    func group(id: UUID) -> CollectionRow? {
        groups.first { $0.id == id }
    }
}
