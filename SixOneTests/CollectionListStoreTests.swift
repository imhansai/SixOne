//
//  CollectionListStoreTests.swift
//  SixOneTests
//  分组列表：后台加载与分组事件重载。
//

import Foundation
import Testing
@testable import SixOne

@Suite("分组列表")
@MainActor
struct CollectionListStoreTests {
    @Test("初始加载分组，收到分组事件后重载")
    func loadsAndReloads() async throws {
        let repository = FakeHistoryRepository()
        await repository.setCollections([row("Work")])
        let events = ClipboardHistoryEventBus()
        let store = CollectionListStore(repository: repository, events: events)

        await store.waitForPendingLoad()
        #expect(store.groups.map(\.name) == ["Work"])

        await repository.setCollections([row("Work"), row("Personal")])
        events.post(.collectionsChanged)

        #expect(await Wait.until { store.groups.count == 2 })
        #expect(store.groups.map(\.name) == ["Work", "Personal"])
    }

    private func row(_ name: String) -> CollectionRow {
        CollectionRow(id: UUID(), name: name, createdAt: Date())
    }
}
