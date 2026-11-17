//
//  ClipboardCollectionTests.swift
//  SixOneTests
//  分组写入：名称归一化、增删改、归属只动元数据。
//

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("分组写入")
@MainActor
struct ClipboardCollectionTests {
    @Test("分组名归一化：折叠空白、拒绝空名、截断超长")
    func normalizesCollectionName() {
        #expect(CollectionNameNormalizer.normalized("  工作\n邮箱  ") == "工作 邮箱")
        #expect(CollectionNameNormalizer.normalized(" \n\t ") == nil)
        #expect(CollectionNameNormalizer.normalized(nil) == nil)

        let long = String(repeating: "a", count: CollectionNameNormalizer.maxLength + 10)
        #expect(CollectionNameNormalizer.normalized(long)?.count == CollectionNameNormalizer.maxLength)
    }

    @Test("分组编辑器模式：新建与重命名的标题、按钮与初始值")
    func collectionEditorModes() {
        #expect(CollectionEditor.Mode.create.title == Localizer.string("New Group"))
        #expect(CollectionEditor.Mode.create.actionTitle == Localizer.string("Create"))
        #expect(CollectionEditor.Mode.create.initialName == "")

        let rename = CollectionEditor.Mode.rename(currentName: "Work")
        #expect(rename.title == Localizer.string("Rename Group"))
        #expect(rename.actionTitle == Localizer.string("Rename"))
        #expect(rename.initialName == "Work")
    }

    @Test("新建分组：归一化落库、广播事件、拒绝重名与空名")
    func createsCollection() throws {
        let env = try Env()
        let id = try env.writer.createCollection(named: "  Work  ").get()

        let collections = try env.collections()
        #expect(collections.map(\.id) == [id])
        #expect(collections.map(\.name) == ["Work"])
        #expect(env.recorder.events == [.collectionsChanged])

        #expect(
            env.writer.createCollection(named: "work") == .failure(.duplicateName),
            "重名判定应忽略大小写"
        )
        #expect(env.writer.createCollection(named: "   ") == .failure(.emptyName))
    }

    @Test("重命名分组：改元数据、广播事件、拒绝重名与空名")
    func renamesCollection() throws {
        let env = try Env()
        let id = try env.writer.createCollection(named: "Work").get()
        let other = try env.writer.createCollection(named: "Personal").get()
        env.recorder.events.removeAll()

        try env.writer.renameCollection(id: id, named: "  工作  ").get()
        let collections = try env.collections()
        #expect(collections.first { $0.id == id }?.name == "工作")
        #expect(env.recorder.events == [.collectionsChanged])

        #expect(
            failure(env.writer.renameCollection(id: id, named: "personal")) == .duplicateName
        )
        #expect(failure(env.writer.renameCollection(id: id, named: "  ")) == .emptyName)
        #expect(
            failure(env.writer.renameCollection(id: UUID(), named: "新名字")) == .notFound
        )
        #expect(collections.first { $0.id == other }?.name == "Personal")
    }

    @Test("设置分组：只改归属，不刷新排序键与活动时间")
    func assignsCollectionWithoutTouchingRecency() throws {
        let env = try Env()
        let item = try env.makeItem("工作条目")
        let collection = try env.writer.createCollection(named: "Work").get()
        let originalRecency = item.recencyID
        let originalActivity = item.lastActivityAt
        env.recorder.events.removeAll()

        #expect(env.writer.assignCollection(itemID: item.id, collectionID: collection))
        #expect(item.collectionID == collection)
        #expect(item.recencyID == originalRecency, "设置分组不该改变排序")
        #expect(item.lastActivityAt == originalActivity, "设置分组不该刷新活动时间")
        #expect(env.recorder.events == [.rowUpdated(id: item.id)])

        #expect(env.writer.assignCollection(itemID: item.id, collectionID: nil))
        #expect(item.collectionID == nil)
        #expect(env.recorder.events.last == .rowUpdated(id: item.id))
        #expect(
            !env.writer.assignCollection(itemID: item.id, collectionID: UUID()),
            "不存在的分组不应写入"
        )
    }

    @Test("删除分组：成员回到未分组，条目本身不删")
    func deletesCollectionWithoutDeletingItems() throws {
        let env = try Env()
        let item = try env.makeItem("保留条目")
        let collection = try env.writer.createCollection(named: "Work").get()
        #expect(env.writer.assignCollection(itemID: item.id, collectionID: collection))
        env.recorder.events.removeAll()

        #expect(env.writer.deleteCollection(id: collection))
        #expect(try env.collections().isEmpty)
        let items = try env.context.fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.map(\.id) == [item.id])
        #expect(item.collectionID == nil)
        #expect(env.recorder.events == [.collectionsChanged])
    }

    @Test("新建分组保存失败：回滚、不发事件")
    func rollsBackFailedCollectionInsert() throws {
        let env = try Env(persist: { throw SaveFailure.simulated })
        let result = env.writer.createCollection(named: "Work")

        #expect(result == .failure(.persistence))
        #expect(env.recorder.events.isEmpty)
        #expect(try env.collections().isEmpty)
    }

    @Test("删除分组保存失败：分组与归属都还在")
    func rollsBackFailedCollectionDelete() throws {
        let env = try Env()
        let item = try env.makeItem("保留条目")
        let collection = try env.writer.createCollection(named: "Work").get()
        #expect(env.writer.assignCollection(itemID: item.id, collectionID: collection))
        env.recorder.events.removeAll()

        let failing = ClipboardHistoryWriter(
            container: env.container,
            events: env.events,
            persist: { throw SaveFailure.simulated }
        )
        #expect(!failing.deleteCollection(id: collection))
        #expect(try env.collections().map(\.id) == [collection])
        #expect(item.collectionID == collection)
        #expect(env.recorder.events.isEmpty)
    }

    private func failure<T>(
        _ result: Result<T, CollectionMutationFailure>
    ) -> CollectionMutationFailure? {
        if case .failure(let failure) = result { return failure }
        return nil
    }

    @MainActor
    private final class Recorder {
        var events: [ClipboardHistoryEvent] = []
    }

    @MainActor
    private struct Env {
        let container: ModelContainer
        let context: ModelContext
        let events: ClipboardHistoryEventBus
        let recorder: Recorder
        let writer: ClipboardHistoryWriter

        init(persist: (() throws -> Void)? = nil) throws {
            let schema = Schema([ClipboardItem.self, ClipboardCollection.self])
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            let events = ClipboardHistoryEventBus()
            let recorder = Recorder()
            events.observe { [recorder] in recorder.events.append($0) }
            self.container = container
            self.context = container.mainContext
            self.events = events
            self.recorder = recorder
            self.writer = ClipboardHistoryWriter(
                container: container,
                events: events,
                persist: persist
            )
        }

        func makeItem(_ text: String) throws -> ClipboardItem {
            let item = ClipboardItem(kind: .text, text: text)
            item.refreshTitleSnapshot()
            item.refreshContentKey()
            context.insert(item)
            try context.save()
            return item
        }

        func collections() throws -> [ClipboardCollection] {
            try context.fetch(FetchDescriptor<ClipboardCollection>())
        }
    }

    private enum SaveFailure: Error {
        case simulated
    }
}
