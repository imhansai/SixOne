//
//  ClipboardCollectionRepositoryTests.swift
//  SixOneTests
//  分组筛选与搜索共用同一次读取；分组行按名称排序。
//

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("分组读取")
@MainActor
struct ClipboardCollectionRepositoryTests {
    @Test("分组筛选只返回组内条目，未分组按 nil 归集")
    func filtersByCollectionAndUngrouped() async throws {
        let env = try Env()
        let work = env.collection("Work")
        let personal = env.collection("Personal")
        let workItem = env.text("工作条目", collection: work)
        let personalItem = env.text("个人条目", collection: personal)
        let ungrouped = env.text("未分组条目")
        try env.save()

        let workRows = try await env.repository.latest(
            query: HistoryQuery(collection: .collection(work.id)),
            limit: 10
        )
        #expect(workRows.map(\.id) == [workItem.id])

        let ungroupedRows = try await env.repository.latest(
            query: HistoryQuery(collection: .ungrouped),
            limit: 10
        )
        #expect(ungroupedRows.map(\.id) == [ungrouped.id])

        let allRows = try await env.repository.latest(
            query: HistoryQuery(collection: .all),
            limit: 10
        )
        #expect(Set(allRows.map(\.id)) == Set([workItem.id, personalItem.id, ungrouped.id]))
    }

    @Test("搜索词与分组条件同时生效")
    func combinesSearchAndCollection() async throws {
        let env = try Env()
        let work = env.collection("Work")
        let personal = env.collection("Personal")
        let workReport = env.text("季度报告", collection: work)
        _ = env.text("周报", collection: work)
        _ = env.text("季度报告", collection: personal)
        try env.save()

        let workRows = try await env.repository.latest(
            query: HistoryQuery(text: "季度", collection: .collection(work.id)),
            limit: 10
        )
        #expect(workRows.map(\.id) == [workReport.id])

        let ungroupedRows = try await env.repository.latest(
            query: HistoryQuery(text: "季度", collection: .ungrouped),
            limit: 10
        )
        #expect(ungroupedRows.isEmpty)
    }

    @Test("游标补位遵循分组条件")
    func rowsAfterCursorHonorsCollection() async throws {
        let env = try Env()
        let work = env.collection("Work")
        let first = env.text("第一条", collection: work)
        _ = env.text("第二条")
        let third = env.text("第三条", collection: work)
        _ = env.text("第四条")
        let fifth = env.text("第五条", collection: work)
        try env.save()

        let older = try await env.repository.rows(
            after: fifth.recencyID,
            query: HistoryQuery(collection: .collection(work.id)),
            limit: 10
        )
        #expect(older.map(\.id) == [third.id, first.id])
    }

    @Test("单行命中校验同时看分组与搜索词")
    func rowMatchesHonorsCollectionAndText() async throws {
        let env = try Env()
        let work = env.collection("Work")
        let other = env.collection("Other")
        let item = env.text("季度报告", collection: work)
        try env.save()

        #expect(try await env.repository.rowMatches(
            id: item.id,
            query: HistoryQuery(text: "季度", collection: .collection(work.id))
        ))
        #expect(try await env.repository.rowMatches(
            id: item.id,
            query: HistoryQuery(collection: .ungrouped)
        ) == false)
        #expect(try await env.repository.rowMatches(
            id: item.id,
            query: HistoryQuery(collection: .collection(other.id))
        ) == false)
        #expect(try await env.repository.rowMatches(
            id: item.id,
            query: HistoryQuery(text: "周报", collection: .collection(work.id))
        ) == false)
    }

    @Test("行快照带上 collectionID")
    func rowSnapshotCarriesCollectionID() async throws {
        let env = try Env()
        let work = env.collection("Work")
        let item = env.text("工作条目", collection: work)
        try env.save()

        let row = try #require(try await env.repository.row(id: item.id))
        #expect(row.collectionID == work.id)
    }

    @Test("分组列表按名称本地化排序")
    func collectionsAreSortedByName() async throws {
        let env = try Env()
        _ = env.collection("Beta")
        _ = env.collection("alpha")
        _ = env.collection("Gamma")
        try env.save()

        let names = try await env.repository.collections().map(\.name)
        #expect(Set(names) == Set(["Beta", "alpha", "Gamma"]))
        #expect(names == names.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        })
    }

    @MainActor
    private struct Env {
        let container: ModelContainer
        let context: ModelContext
        let repository: SwiftDataHistoryRepository

        init() throws {
            let schema = Schema([ClipboardItem.self, ClipboardCollection.self])
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            self.container = container
            self.context = container.mainContext
            self.repository = SwiftDataHistoryRepository(container: container)
        }

        func collection(_ name: String) -> ClipboardCollection {
            let collection = ClipboardCollection(name: name)
            context.insert(collection)
            return collection
        }

        func text(_ text: String, collection: ClipboardCollection? = nil) -> ClipboardItem {
            let item = ClipboardItem(
                kind: .text,
                text: text,
                collectionID: collection?.id
            )
            item.refreshTitleSnapshot()
            item.refreshContentKey()
            context.insert(item)
            return item
        }

        func save() throws {
            try context.save()
        }
    }
}
