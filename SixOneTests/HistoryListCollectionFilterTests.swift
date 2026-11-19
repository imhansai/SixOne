//
//  HistoryListCollectionFilterTests.swift
//  SixOneTests
//  列表在分组筛选下的加载、增量插入、触达与归属变化。
//

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("列表分组筛选")
@MainActor
struct HistoryListCollectionFilterTests {
    @Test("点分组只切换该组：再点同一组回到全部数据")
    func togglingCollectionFilter() {
        let first = UUID()
        let second = UUID()

        #expect(CollectionFilter.all.toggled(first) == .collection(first))
        #expect(CollectionFilter.collection(first).toggled(second) == .collection(second))
        #expect(CollectionFilter.collection(first).toggled(first) == .all)
    }

    @Test("收起期间有新复制：唤出时放弃分组筛选；没有新内容则保留")
    func restoresFilterOnShow() {
        let collectionID = UUID()

        #expect(
            CollectionFilter.collection(collectionID).restoredOnShow(hasNewContent: true)
                == .all
        )
        #expect(
            CollectionFilter.collection(collectionID).restoredOnShow(hasNewContent: false)
                == .collection(collectionID)
        )
        #expect(CollectionFilter.all.restoredOnShow(hasNewContent: true) == .all)
    }

    @Test("切分组只加载组内条目，取消筛选恢复全部")
    func loadsFilteredWindow() async throws {
        let env = try Env()
        let work = env.collection("Work")
        let personal = env.collection("Personal")
        let workItem = env.item("工作", collection: work.id)
        let personalItem = env.item("个人", collection: personal.id)
        let ungrouped = env.item("未分组")
        try env.save()

        env.store.setQuery(HistoryQuery(collection: .collection(work.id)))
        await env.store.waitForPendingLoad()
        #expect(env.store.rows.map(\.id) == [workItem.id])
        #expect(env.store.rows.allSatisfy { $0.collectionID == work.id })

        // 再点一次选中的分组：取消筛选，全部数据（含未分组）回来。
        env.store.setQuery(HistoryQuery(collection: env.store.collectionFilter.toggled(work.id)))
        await env.store.waitForPendingLoad()
        #expect(env.store.collectionFilter == .all)
        #expect(
            Set(env.store.rows.map(\.id))
                == Set([workItem.id, personalItem.id, ungrouped.id])
        )
    }

    @Test("搜索词与分组一次落定，只命中组内匹配项")
    func searchWithinCollection() async throws {
        let env = try Env()
        let work = env.collection("Work")
        let match = env.item("季度报告", collection: work.id)
        _ = env.item("周报", collection: work.id)
        _ = env.item("季度报告")
        try env.save()

        env.store.setQuery(HistoryQuery(text: "季度", collection: .collection(work.id)))
        await env.store.waitForPendingLoad()

        #expect(env.store.rows.map(\.id) == [match.id])
        #expect(env.store.matches(
            HistoryQuery(text: "季度", collection: .collection(work.id))
        ))
        #expect(!env.store.matches(HistoryQuery(text: "季度", collection: .all)))
    }

    @Test("分组态收到组外新条目：不进入当前窗口")
    func insertedOutsideFilterIsIgnored() async throws {
        let env = try Env()
        let work = env.collection("Work")
        let inGroup = env.item("组内", collection: work.id)
        try env.save()

        env.store.setQuery(HistoryQuery(collection: .collection(work.id)))
        await env.store.waitForPendingLoad()

        let outside = env.item("组外")
        try env.save()
        env.events.post(.inserted(id: outside.id))
        await env.settle()

        #expect(env.store.rows.map(\.id) == [inGroup.id])
        #expect(!env.store.rows.contains { $0.id == outside.id })
    }

    @Test("分组态收到组内新条目：重载后可见")
    func insertedInsideFilterAppears() async throws {
        let env = try Env()
        let work = env.collection("Work")
        _ = env.item("已有", collection: work.id)
        try env.save()

        env.store.setQuery(HistoryQuery(collection: .collection(work.id)))
        await env.store.waitForPendingLoad()

        let newItem = env.item("新组内", collection: work.id)
        try env.save()
        env.events.post(.inserted(id: newItem.id))
        await env.settle()

        #expect(env.store.rows.contains { $0.id == newItem.id })
    }

    @Test("分组态触达组外条目：不重载当前窗口")
    func touchedOutsideFilterIsIgnored() async throws {
        let env = try Env()
        let work = env.collection("Work")
        let inGroup = env.item("组内", collection: work.id)
        let outside = env.item("组外")
        try env.save()

        env.store.setQuery(HistoryQuery(collection: .collection(work.id)))
        await env.store.waitForPendingLoad()
        let revision = env.store.dataRevision

        env.events.post(.touched(id: outside.id))
        await env.settle()

        #expect(env.store.rows.map(\.id) == [inGroup.id])
        #expect(env.store.dataRevision == revision, "组外触达不该重载当前窗口")
    }

    @Test("归属变化：移入当前分组可见，移出后消失")
    func rowUpdatedAcrossFilter() async throws {
        let env = try Env()
        let work = env.collection("Work")
        let inGroup = env.item("组内", collection: work.id)
        let moving = env.item("待移动")
        try env.save()

        env.store.setQuery(HistoryQuery(collection: .collection(work.id)))
        await env.store.waitForPendingLoad()
        #expect(env.store.rows.map(\.id) == [inGroup.id])

        try env.assign(moving.id, to: work.id)
        env.events.post(.rowUpdated(id: moving.id))
        await env.settle()
        #expect(env.store.rows.contains { $0.id == moving.id })

        try env.assign(inGroup.id, to: nil)
        env.events.post(.rowUpdated(id: inGroup.id))
        await env.settle()
        #expect(!env.store.rows.contains { $0.id == inGroup.id })
        #expect(env.store.rows.contains { $0.id == moving.id })
    }

    @Test("分组态删除只从组内补位，不混入组外条目")
    func deleteUnderFilterStaysInGroup() async throws {
        let env = try Env()
        let work = env.collection("Work")
        let first = env.item("第一条", collection: work.id)
        let middle = env.item("第二条", collection: work.id)
        let last = env.item("第三条", collection: work.id)
        _ = env.item("组外")
        try env.save()

        env.store.setQuery(HistoryQuery(collection: .collection(work.id)))
        await env.store.waitForPendingLoad()

        try env.delete(middle.id)
        env.events.post(.deleted(id: middle.id))
        await env.settle()

        #expect(Set(env.store.rows.map(\.id)) == Set([first.id, last.id]))
        #expect(!env.store.rows.contains { $0.collectionID == nil })
    }

    @MainActor
    private struct Env {
        let container: ModelContainer
        let context: ModelContext
        let events: ClipboardHistoryEventBus
        let store: HistoryListStore

        init() throws {
            let schema = Schema([ClipboardItem.self, ClipboardCollection.self])
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            let events = ClipboardHistoryEventBus()
            self.container = container
            self.context = container.mainContext
            self.events = events
            self.store = HistoryListStore(
                repository: SwiftDataHistoryRepository(container: container),
                events: events
            )
        }

        func collection(_ name: String) -> ClipboardCollection {
            let collection = ClipboardCollection(name: name)
            context.insert(collection)
            return collection
        }

        func item(_ text: String, collection: UUID? = nil) -> ClipboardItem {
            let item = ClipboardItem(kind: .text, text: text, collectionID: collection)
            item.refreshTitleSnapshot()
            item.refreshContentKey()
            context.insert(item)
            return item
        }

        func assign(_ itemID: UUID, to collectionID: UUID?) throws {
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.id == itemID }
            )
            descriptor.fetchLimit = 1
            guard let item = try context.fetch(descriptor).first else { return }
            item.collectionID = collectionID
            try context.save()
        }

        func delete(_ itemID: UUID) throws {
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.id == itemID }
            )
            descriptor.fetchLimit = 1
            guard let item = try context.fetch(descriptor).first else { return }
            context.delete(item)
            try context.save()
        }

        func save() throws {
            try context.save()
        }

        func settle() async {
            await store.waitForPendingEvents()
            await store.waitForPendingLoad()
        }
    }
}
