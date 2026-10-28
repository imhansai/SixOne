//
//  HistoryListRefreshTests.swift
//  SixOneTests

import Foundation
import SwiftData
import Testing
@testable import SixOne

/// 刷新策略：顶部立刻重载，深处保留窗口、回顶再补；每个 Harness 自带总线，可并行。
@Suite("历史列表刷新策略")
@MainActor
struct HistoryListRefreshTests {
    @Test("查询词归一化后一致才算已生效")
    func matchesNormalizedQuery() async throws {
        let harness = try Harness(itemCount: 3)

        #expect(harness.store.matchesQuery(""))
        #expect(harness.store.matchesQuery("  \n "))
        #expect(!harness.store.matchesQuery("任意词"))

        harness.store.setSearchQuery("复制")
        #expect(harness.store.isSearching)
        #expect(harness.store.matchesQuery("复制"))
        #expect(!harness.store.matchesQuery("复制 "))
    }

    @Test("停在顶部时收到新拷贝立刻重载")
    func refreshesAtTop() async throws {
        let harness = try Harness(itemCount: 250)
        await harness.store.loadLatestAndWait()
        harness.store.noteTopVisibleIndex(0)
        let revision = harness.store.dataRevision

        try harness.copy("新条目")
        await settle(harness.store)

        #expect(harness.store.dataRevision != revision)
    }

    @Test("滚到深处收到新拷贝不动窗口，回到顶部才重载")
    func defersRefreshWhileDeep() async throws {
        let harness = try Harness(itemCount: 250)
        await harness.store.loadLatestAndWait()
        harness.store.noteTopVisibleIndex(50)
        let anchoredTop = harness.store.rows.first?.id
        let revision = harness.store.dataRevision

        try harness.copy("新条目")
        await settle(harness.store)

        #expect(harness.store.rows.first?.id == anchoredTop)
        #expect(harness.store.dataRevision == revision)

        harness.store.noteTopVisibleIndex(0)
        await harness.store.waitForPendingLoad()
        #expect(harness.store.dataRevision != revision)
        #expect(harness.store.rows.first?.id != anchoredTop)
    }

    @Test("收起期间的拷贝直接在收起时落定，不必等回到顶部")
    func refreshesWhileHidden() async throws {
        let harness = try Harness(itemCount: 250)
        await harness.store.loadLatestAndWait()
        harness.store.noteTopVisibleIndex(120)
        let revision = harness.store.dataRevision
        let anchoredTop = harness.store.rows.first?.id

        harness.store.setListVisible(false)
        let newID = try harness.copy("收起期间的新条目")
        await settle(harness.store)

        #expect(harness.store.dataRevision != revision, "收起期间的数据变化被攒住了")
        #expect(harness.store.rows.first?.id == newID, "窗口没有换成最新一窗")
        #expect(harness.store.rows.first?.id != anchoredTop)
    }

    @Test("收起期间的新复制记为「唤出回顶部」，看着的时候来的不算")
    func tracksNewContentWhileHidden() async throws {
        let harness = try Harness(itemCount: 250)
        await harness.store.loadLatestAndWait()
        harness.store.noteTopVisibleIndex(120)

        try harness.copy("看着的时候来的")
        await settle(harness.store)
        #expect(!harness.store.takeNewContentWhileHidden())

        harness.store.setListVisible(false)
        try harness.copy("收起的时候来的")
        await settle(harness.store)

        #expect(harness.store.takeNewContentWhileHidden())
        #expect(!harness.store.takeNewContentWhileHidden(), "标记只能取一次")
    }

    @Test("收起期间的面板内触达置顶不算新内容，深浏览的位置照旧恢复")
    func ignoresTouchWhileHidden() async throws {
        let harness = try Harness(itemCount: 3)
        await harness.store.loadLatestAndWait()
        harness.store.setListVisible(false)

        harness.events.post(.touched(id: harness.itemIDs[0]))
        // 事件处理延后一跳；等条目真的置顶，才能确认它已被消费。
        #expect(await Wait.until { harness.store.rows.first?.id == harness.itemIDs[0] })

        #expect(!harness.store.takeNewContentWhileHidden())
    }

    @Test("收起期间外部复制命中已有条目（去重置顶）也算新内容")
    func tracksExternalTouchWhileHidden() async throws {
        let harness = try Harness(itemCount: 3)
        await harness.store.loadLatestAndWait()
        harness.store.setListVisible(false)

        harness.events.post(.touched(id: harness.itemIDs[0], isExternal: true))
        #expect(await Wait.until { harness.store.rows.first?.id == harness.itemIDs[0] })

        #expect(harness.store.takeNewContentWhileHidden())
    }

    @Test("收起时把已经攒下的刷新补上")
    func flushesPendingRefreshOnHide() async throws {
        let harness = try Harness(itemCount: 250)
        await harness.store.loadLatestAndWait()
        harness.store.noteTopVisibleIndex(120)
        let revision = harness.store.dataRevision

        let newID = try harness.copy("深处攒下的新条目")
        await settle(harness.store)
        #expect(harness.store.dataRevision == revision, "看着深处时不该动窗口")

        harness.store.setListVisible(false)
        await settle(harness.store)
        #expect(harness.store.dataRevision != revision, "收起没有补上攒下的刷新")
        #expect(harness.store.rows.first?.id == newID)
    }

    @Test("停在下方清空历史也立刻变空，不必滚回顶部")
    func clearsImmediatelyWhileDeep() async throws {
        let harness = try Harness(itemCount: 250)
        await harness.store.loadLatestAndWait()
        harness.store.noteTopVisibleIndex(120)
        #expect(!harness.store.rows.isEmpty)

        try harness.clearAll()
        await settle(harness.store)

        #expect(harness.store.rows.isEmpty)
        #expect(!harness.store.hasOlder)

        try harness.copy("清空后的第一条")
        await settle(harness.store)
        #expect(harness.store.rows.count == 1)
    }

    @Test("清空后失效条目不再被当成还在，预览与选中据此收尾")
    func itemExistenceProbe() async throws {
        let harness = try Harness(itemCount: 3)
        let firstID = harness.itemIDs[0]

        #expect(await harness.store.itemExists(id: firstID))
        #expect(!(await harness.store.itemExists(id: UUID())))

        try harness.clearAll()
        await settle(harness.store)

        #expect(!(await harness.store.itemExists(id: firstID)))
    }

    @Test("读库失败：保留旧行，但把失败标出来")
    func reportsReadFailure() async throws {
        let repository = FakeHistoryRepository(rowsByQuery: ["": [.stub(title: "第一条")]])
        let store = HistoryListStore(repository: repository, events: ClipboardHistoryEventBus())

        await store.loadLatestAndWait()
        #expect(!store.didFailToLoad)
        #expect(store.rows.count == 1)

        // 读库失败保留旧行，但须标出失败，否则界面误报空历史。
        await repository.startFailing()
        await store.loadLatestAndWait()

        #expect(store.didFailToLoad)
        #expect(store.rows.count == 1, "读失败时应保留上一批行")

        await repository.stopFailing()
        await store.loadLatestAndWait()

        #expect(!store.didFailToLoad)
    }

    /// 等事件链路走完：先让出主 actor，再等挂起加载；固定轮询或 sleep 都等不准。
    private func settle(_ store: HistoryListStore) async {
        await Task.yield()
        await store.waitForPendingLoad()
    }

    /// 内存库 + 列表数据源；容器由本结构持有，避免中途释放。
    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let events: ClipboardHistoryEventBus
        let store: HistoryListStore
        let itemIDs: [UUID]

        init(itemCount: Int) throws {
            let schema = Schema([ClipboardItem.self])
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            context = container.mainContext
            let events = ClipboardHistoryEventBus()
            self.events = events
            var ids: [UUID] = []
            for index in 0..<itemCount {
                let item = ClipboardItem(kind: .text, text: "条目 \(index)")
                context.insert(item)
                ids.append(item.id)
            }
            try context.save()
            itemIDs = ids
            store = HistoryListStore(
                repository: SwiftDataHistoryRepository(container: container),
                events: events
            )
        }

        @discardableResult
        func copy(_ text: String) throws -> UUID {
            let item = ClipboardItem(kind: .text, text: text)
            context.insert(item)
            try context.save()
            events.post(.inserted(id: item.id))
            return item.id
        }

        func clearAll() throws {
            for item in try context.fetch(FetchDescriptor<ClipboardItem>()) {
                context.delete(item)
            }
            try context.save()
            events.post(.cleared)
        }
    }
}
