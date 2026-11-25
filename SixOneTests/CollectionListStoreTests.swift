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
        #expect(store.groupNamesByID == [store.groups[0].id: "Work"], "名字索引随加载一起就绪")

        await repository.setCollections([row("Work"), row("Personal")])
        events.post(.collectionsChanged)

        #expect(await Wait.until { store.groups.count == 2 })
        #expect(store.groups.map(\.name) == ["Work", "Personal"])
        #expect(
            store.groupNamesByID == Dictionary(
                uniqueKeysWithValues: store.groups.map { ($0.id, $0.name) }
            ),
            "重载后名字索引与分组列表同步"
        )
    }

    @Test("迟到的旧加载不会覆盖较新的加载结果")
    func staleLoadDoesNotOverwriteNewerResult() async throws {
        let repository = GatedCollectionsRepository()
        await repository.gateNextCall()
        await repository.setResponse([row("Old")])
        await repository.setResponse([row("New")])

        let store = CollectionListStore(
            repository: repository,
            events: ClipboardHistoryEventBus()
        )
        // init 已经发起第一次加载；等它被闸住再开始第二次。
        #expect(await Wait.untilAsync { await repository.startedCalls == 1 })
        store.reload()
        #expect(await Wait.untilAsync { await repository.startedCalls == 2 })
        #expect(await Wait.until { store.groups.map(\.name) == ["New"] })

        await repository.releaseGate()
        #expect(await Wait.untilAsync { await repository.finishedCalls == 2 })
        #expect(store.groups.map(\.name) == ["New"], "旧结果回来晚了，但读取代号已经不匹配")
    }

    private func row(_ name: String) -> CollectionRow {
        CollectionRow(id: UUID(), name: name, createdAt: Date())
    }
}

/// 可控时序的分组读取：第一次调用可被闸住，验证迟到的旧结果被丢弃。
private actor GatedCollectionsRepository: ClipboardHistoryRepository {
    private var responses: [[CollectionRow]] = []
    private var gatedCalls = 0
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var startedCalls = 0
    private(set) var finishedCalls = 0

    func setResponse(_ rows: [CollectionRow]) {
        responses.append(rows)
    }

    func gateNextCall() {
        gatedCalls += 1
    }

    func releaseGate() {
        gate?.resume()
        gate = nil
    }

    func collections() async throws -> [CollectionRow] {
        startedCalls += 1
        let rows = responses.isEmpty ? [] : responses.removeFirst()
        if gatedCalls > 0 {
            gatedCalls -= 1
            await withCheckedContinuation { gate = $0 }
        }
        finishedCalls += 1
        return rows
    }

    func latest(query: HistoryQuery, limit: Int) async throws -> [HistoryRow] { [] }

    func rows(after cursor: UUID, query: HistoryQuery, limit: Int) async throws -> [HistoryRow] { [] }

    func row(id: UUID) async throws -> HistoryRow? { nil }

    func rowMatches(id: UUID, query: HistoryQuery) async throws -> Bool { false }

    func itemExists(id: UUID) async throws -> Bool { false }

    func sourceApplications(limit: Int) async throws -> [String] { [] }
}
