//
//  HistoryListFilterTests.swift
//  SixOneTests
//  列表在类型 / 来源 / 日期筛选下的加载、增量插入与触达判定。
//

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("列表综合筛选")
@MainActor
struct HistoryListFilterTests {
    @Test("按类型筛选只加载命中的条目，取消后恢复全部")
    func loadsKindFilteredWindow() async throws {
        let env = try Env()
        let text = env.item("文字")
        let image = env.item("图片", kind: .image)
        let file = env.item("文件", kind: .file)
        try env.save()

        env.store.setFilter(HistoryFilter(kinds: [.image, .file]))
        await env.store.waitForPendingLoad()

        #expect(env.store.isFiltering)
        #expect(env.store.filter.kinds == [.image, .file])
        #expect(env.store.rows.map(\.id) == [file.id, image.id])

        env.store.setFilter(.none)
        await env.store.waitForPendingLoad()
        #expect(!env.store.isFiltering)
        #expect(
            Set(env.store.rows.map(\.id))
                == Set([text.id, image.id, file.id])
        )
    }

    @Test("类型筛选态收到筛选外的新条目：不进入当前窗口")
    func insertedOutsideKindFilterIsIgnored() async throws {
        let env = try Env()
        let image = env.item("图片", kind: .image)
        try env.save()

        env.store.setFilter(HistoryFilter(kinds: [.image]))
        await env.store.waitForPendingLoad()

        let text = env.item("新文字")
        try env.save()
        env.events.post(.inserted(id: text.id))
        await env.settle()

        #expect(env.store.rows.map(\.id) == [image.id])
    }

    @Test("类型筛选态收到命中新条目：重载后可见")
    func insertedInsideKindFilterAppears() async throws {
        let env = try Env()
        let existing = env.item("已有图片", kind: .image)
        try env.save()

        env.store.setFilter(HistoryFilter(kinds: [.image]))
        await env.store.waitForPendingLoad()

        let newImage = env.item("新图片", kind: .image)
        try env.save()
        env.events.post(.inserted(id: newImage.id))
        await env.settle()

        #expect(env.store.rows.map(\.id) == [newImage.id, existing.id])
    }

    @Test("类型筛选态触达筛选外条目：不重载当前窗口")
    func touchedOutsideKindFilterIsIgnored() async throws {
        let env = try Env()
        _ = env.item("图片", kind: .image)
        try env.save()

        env.store.setFilter(HistoryFilter(kinds: [.image]))
        await env.store.waitForPendingLoad()
        let revision = env.store.dataRevision

        let text = env.item("文字")
        try env.save()
        env.events.post(.touched(id: text.id, isExternal: true))
        await env.settle()

        #expect(env.store.dataRevision == revision, "筛选外触达不该重载当前窗口")
        #expect(env.store.rows.allSatisfy { $0.kind == .image })
    }

    @Test("类型筛选态触达窗口外但命中的条目：重载并置顶")
    func touchedMatchingItemOutsideWindowLoads() async throws {
        let env = try Env()
        _ = env.item("图片", kind: .image)
        try env.save()

        env.store.setFilter(HistoryFilter(kinds: [.image]))
        await env.store.waitForPendingLoad()

        let newImage = env.item("窗口外图片", kind: .image)
        try env.save()
        env.events.post(.touched(id: newImage.id, isExternal: true))
        await env.settle()

        #expect(env.store.rows.first?.id == newImage.id)
    }

    @Test("筛选态触达窗口内条目：不再命中时移出窗口")
    func touchedRowLeavingFilterIsRemoved() async throws {
        let env = try Env()
        let safari = env.item("Safari", source: "com.apple.Safari")
        let yesterday = env.item("昨天", lastActivityAt: Date().addingTimeInterval(-86_400))
        try env.save()

        env.store.setFilter(HistoryFilter(sourceApps: ["com.apple.Safari"]))
        await env.store.waitForPendingLoad()
        #expect(env.store.rows.map(\.id) == [safari.id])

        // 同内容改从 Notes 复制：来源被改写，行不再命中 Safari 筛选。
        try env.touch(safari.id, source: "com.apple.Notes")
        await env.settle()
        #expect(env.store.rows.isEmpty)

        env.store.setFilter(HistoryFilter(dateRanges: [.yesterday]))
        await env.store.waitForPendingLoad()
        #expect(env.store.rows.map(\.id) == [yesterday.id])

        // 触达把时间刷新到现在，行不再属于「昨天」。
        try env.touch(yesterday.id)
        await env.settle()
        #expect(env.store.rows.isEmpty)
    }

    @Test("来源筛选态下归属变化：命中则出现，移出则消失")
    func rowUpdatedAcrossSourceFilter() async throws {
        let env = try Env()
        let safari = env.item("Safari", source: "com.apple.Safari")
        try env.save()

        env.store.setFilter(HistoryFilter(sourceApps: ["com.apple.Safari"]))
        await env.store.waitForPendingLoad()
        #expect(env.store.rows.map(\.id) == [safari.id])

        let moved = env.item("将改成 Notes", source: "com.apple.Notes")
        try env.save()

        try env.assignSource(moved.id, to: "com.apple.Safari")
        env.events.post(.rowUpdated(id: moved.id))
        await env.settle()
        #expect(env.store.rows.contains { $0.id == moved.id })

        try env.assignSource(moved.id, to: "com.apple.Notes")
        env.events.post(.rowUpdated(id: moved.id))
        await env.settle()
        #expect(!env.store.rows.contains { $0.id == moved.id })
        #expect(env.store.rows.contains { $0.id == safari.id })
    }

    @Test("日期筛选只加载区间内条目")
    func loadsDateFilteredWindow() async throws {
        let env = try Env()
        let recent = env.item("最近")
        let old = env.item("更早", lastActivityAt: Date().addingTimeInterval(-40 * 86_400))
        try env.save()

        env.store.setFilter(HistoryFilter(dateRanges: [.today]))
        await env.store.waitForPendingLoad()
        #expect(env.store.rows.map(\.id) == [recent.id])

        env.store.setFilter(HistoryFilter(dateRanges: [.older]))
        await env.store.waitForPendingLoad()
        #expect(env.store.rows.map(\.id) == [old.id])
    }

    @Test("来源候选列表走仓库，按最近出现去重")
    func sourceApplicationsComeFromRepository() async throws {
        let env = try Env()
        _ = env.item("a", source: "com.apple.Safari")
        _ = env.item("b", source: "com.apple.Notes")
        _ = env.item("c", source: "com.apple.Safari")
        _ = env.item("d")
        try env.save()

        #expect(
            await env.store.sourceApplications()
                == ["com.apple.Safari", "com.apple.Notes"]
        )
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

        func item(
            _ text: String,
            kind: ClipboardItemKind = .text,
            source: String? = nil,
            lastActivityAt: Date = Date(),
            collection: UUID? = nil
        ) -> ClipboardItem {
            let item: ClipboardItem
            switch kind {
            case .text, .link, .color:
                item = ClipboardItem(
                    kind: kind,
                    text: text,
                    sourceAppBundleIdentifier: source,
                    collectionID: collection
                )
            case .image:
                item = ClipboardItem(
                    kind: .image,
                    imageData: Data(text.utf8),
                    sourceAppBundleIdentifier: source,
                    collectionID: collection
                )
            case .file:
                item = ClipboardItem(
                    kind: .file,
                    filePaths: ["/tmp/\(text)"],
                    sourceAppBundleIdentifier: source,
                    collectionID: collection
                )
            }
            item.lastActivityAt = lastActivityAt
            item.refreshTitleSnapshot()
            item.refreshContentKey()
            context.insert(item)
            return item
        }

        func assignSource(_ itemID: UUID, to source: String?) throws {
            guard let item = try fetchItem(itemID) else { return }
            item.sourceAppBundleIdentifier = source
            try context.save()
        }

        /// 复刻 writer 的触达：刷新时间与排序键，可选改写来源，再广播事件。
        func touch(_ itemID: UUID, source: String? = nil) throws {
            guard let item = try fetchItem(itemID) else { return }
            item.lastActivityAt = Date()
            item.recencyID = OrderedUUID.make()
            if let source { item.sourceAppBundleIdentifier = source }
            try context.save()
            events.post(.touched(id: itemID, isExternal: true))
        }

        private func fetchItem(_ itemID: UUID) throws -> ClipboardItem? {
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.id == itemID }
            )
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first
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
