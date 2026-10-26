//
//  ClipboardHistoryRepositoryTests.swift
//  SixOneTests
//  历史读路径与列表异步加载：漏列、窗口截断、迟到覆盖都是静默故障。

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("历史读取")
@MainActor
struct ClipboardHistoryRepositoryTests {
    @Test("取最近一窗按 recencyID 倒序，limit 生效")
    func latestFollowsRecencyOrder() async throws {
        let env = try Env { context in
            (0..<5).map { index in
                let item = ClipboardItem(kind: .text, text: "条目 \(index)")
                context.insert(item)
                return item
            }
        }

        let latestTwo = try await env.repository.latest(query: "", limit: 2)
        #expect(latestTwo.map(\.id) == [env.items[4].id, env.items[3].id])

        let all = try await env.repository.latest(query: "", limit: 10)
        #expect(all.map(\.id) == Array(env.items.map(\.id).reversed()))
    }

    @Test("行快照带上渲染需要的列，文件组个数与路径都在")
    func rowCarriesRenderingColumns() async throws {
        let env = try Env { context in
            let files = ClipboardItem(
                kind: .file,
                filePaths: ["/tmp/a.txt", "/tmp/b.txt", "/tmp/c.txt"]
            )
            files.refreshTitleSnapshot()
            context.insert(files)
            return [files]
        }

        let row = try #require(try await env.repository.row(id: env.items[0].id))
        #expect(row.kind == .file)
        #expect(row.fileCount == 3)
        #expect(row.filePath == "/tmp/a.txt")
        #expect(row.title?.hasPrefix("a.txt") == true)
        #expect(row.title?.contains("2") == true)
    }

    @Test("搜索命中正文、标题与文件路径")
    func searchMatchesTextTitleAndFilePath() async throws {
        let env = try Env { context in
            let text = ClipboardItem(kind: .text, text: "hello world")
            let file = ClipboardItem(kind: .file, filePaths: ["/tmp/quarterly-report.pdf"])
            context.insert(text)
            context.insert(file)
            return [text, file]
        }

        let byText = try await env.repository.latest(query: "hello", limit: 10)
        #expect(byText.map(\.id) == [env.items[0].id])

        let byPath = try await env.repository.latest(query: "quarterly", limit: 10)
        #expect(byPath.map(\.id) == [env.items[1].id])

        let byNothing = try await env.repository.latest(query: "没有这个词", limit: 10)
        #expect(byNothing.isEmpty)
    }

    @Test("条目删除后，存在性探测立刻反映当前状态")
    func existenceFollowsDeletion() async throws {
        let env = try Env { context in
            let item = ClipboardItem(kind: .text, text: "会被删掉")
            context.insert(item)
            return [item]
        }
        let id = env.items[0].id

        #expect(try await env.repository.itemExists(id: id))
        #expect(try await env.repository.itemExists(id: UUID()) == false)

        env.context.delete(env.items[0])
        try env.context.save()

        #expect(try await env.repository.itemExists(id: id) == false)
    }

    @MainActor
    private struct Env {
        let container: ModelContainer
        let context: ModelContext
        let repository: SwiftDataHistoryRepository
        let items: [ClipboardItem]

        init(_ build: (ModelContext) -> [ClipboardItem]) throws {
            let schema = Schema([ClipboardItem.self])
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            let context = container.mainContext
            let items = build(context)
            try context.save()
            self.container = container
            self.context = context
            self.repository = SwiftDataHistoryRepository(container: container)
            self.items = items
        }
    }
}

@Suite("列表异步加载")
@MainActor
struct HistoryListAsyncTests {
    @Test("加载不阻塞调用方：先返回，结果稍后落定")
    func loadReturnsBeforeResult() async throws {
        let repository = FakeHistoryRepository(
            rowsByQuery: ["": [.stub(title: "A")]],
            delaysByQuery: ["": .milliseconds(60)]
        )
        let store = HistoryListStore(repository: repository, events: ClipboardHistoryEventBus())

        store.loadLatest()
        #expect(store.rows.isEmpty)
        #expect(store.isLoading)

        await store.waitForPendingLoad()
        #expect(store.rows.map(\.title) == ["A"])
        #expect(!store.isLoading)
    }

    @Test("先发的查询后返回时，结果整份丢弃，不覆盖新查询")
    func lateResultIsDiscarded() async throws {
        let slow = HistoryRow.stub(title: "慢结果")
        let fast = HistoryRow.stub(title: "快结果")
        let repository = FakeHistoryRepository(
            rowsByQuery: ["慢": [slow], "快": [fast]],
            delaysByQuery: ["慢": .milliseconds(80)]
        )
        let store = HistoryListStore(repository: repository, events: ClipboardHistoryEventBus())

        store.setSearchQuery("慢")
        store.setSearchQuery("快")
        await store.waitForPendingLoad()
        #expect(store.rows.map(\.title) == ["快结果"])

        // 先确认慢查询真的返回过，否则断言恒真通过。
        let slowReturned = await repository.waitUntilReturned("慢")
        #expect(slowReturned, "慢查询没有返回")
        #expect(store.rows.map(\.title) == ["快结果"], "迟到的慢结果把新结果顶掉了")
    }

    @Test("窗口封顶：库里条数多于上限时只取上限条，并置 hasOlder")
    func capsWindowAndFlagsOlder() async throws {
        let rows = (0..<2000).map { HistoryRow.stub(title: "第 \($0) 条") }
        let repository = FakeHistoryRepository(rowsByQuery: ["": rows])
        let store = HistoryListStore(repository: repository, events: ClipboardHistoryEventBus())

        await store.loadLatestAndWait()

        #expect(store.rows.count == store.windowLimit)
        #expect(store.hasOlder)
        #expect(await repository.requestedLimits == [store.windowLimit + 1])
        #expect(await repository.requestedQueries.count == 1)
    }

    @Test("库里条数不超过上限时，没有更早的提示")
    func noOlderFlagWhenWindowNotFull() async throws {
        let rows = (0..<3).map { HistoryRow.stub(title: "第 \($0) 条") }
        let repository = FakeHistoryRepository(rowsByQuery: ["": rows])
        let store = HistoryListStore(repository: repository, events: ClipboardHistoryEventBus())

        await store.loadLatestAndWait()

        #expect(store.rows.count == 3)
        #expect(!store.hasOlder)
    }

    @Test("视图路径会去重：加载中连调 loadLatest 只发一次查询")
    func deduplicatesViewDrivenLoads() async throws {
        let repository = FakeHistoryRepository(
            rowsByQuery: ["": [.stub(title: "A")]],
            delaysByQuery: ["": .milliseconds(50)]
        )
        let store = HistoryListStore(repository: repository, events: ClipboardHistoryEventBus())

        store.loadLatest()
        store.loadLatest()
        store.loadLatest()
        await store.waitForPendingLoad()

        #expect(await repository.requestedQueries.count == 1)
        #expect(store.rows.map(\.title) == ["A"])
    }

    @Test("换搜索词顶掉在途查询：加载中也能立刻换词重查")
    func searchSupersedesInFlightLoad() async throws {
        let oldPage = HistoryRow.stub(title: "旧词结果")
        let newPage = HistoryRow.stub(title: "新词结果")
        let repository = FakeHistoryRepository(
            rowsByQuery: ["旧": [oldPage], "新": [newPage]],
            delaysByQuery: ["旧": .milliseconds(80)]
        )
        let store = HistoryListStore(repository: repository, events: ClipboardHistoryEventBus())

        store.setSearchQuery("旧")
        store.setSearchQuery("新")
        await store.waitForPendingLoad()
        #expect(store.rows.map(\.title) == ["新词结果"])

        // 先确认旧查询真的返回过，否则断言恒真通过。
        let oldReturned = await repository.waitUntilReturned("旧")
        #expect(oldReturned, "旧词的查询没有返回")
        #expect(store.rows.map(\.title) == ["新词结果"], "迟到的旧词结果把新词结果顶掉了")
        #expect(store.query == "新")
    }
}
