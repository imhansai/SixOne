//
//  ClipboardHistoryWriterTests.swift
//  SixOneTests
//  写库失败必须回滚并收住事件，避免界面与磁盘分叉。
//

import AppKit
import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("历史写入失败回滚")
@MainActor
struct ClipboardHistoryWriterTests {
    @Test("新增保存失败：回滚、不发事件、上报失败原因")
    func rollsBackFailedInsert() throws {
        let container = try makeContainer()
        let events = ClipboardHistoryEventBus()
        let recorder = Recorder()
        events.observe { [recorder] in recorder.events.append($0) }

        let writer = ClipboardHistoryWriter(
            container: container,
            events: events,
            persist: { throw SaveFailure.simulated }
        )
        writer.onPersistenceFailure = { [recorder] in recorder.failures.append($0) }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("secret", forType: .string)
        let prepared = try #require(
            PasteboardEntryParser.prepare(from: PasteboardSnapshot.capture(from: [pasteboardItem]))
        )
        writer.commit(prepared, source: nil)

        #expect(recorder.failures == ["新增条目"])
        #expect(recorder.events.isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).isEmpty)
    }

    @Test("删除保存失败：条目还在，不发 deleted")
    func rollsBackFailedDelete() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = ClipboardItem(kind: .text, text: "keep")
        item.refreshTitleSnapshot()
        item.refreshContentKey()
        context.insert(item)
        try context.save()

        let events = ClipboardHistoryEventBus()
        let recorder = Recorder()
        events.observe { [recorder] in recorder.events.append($0) }
        let writer = ClipboardHistoryWriter(
            container: container,
            events: events,
            persist: { throw SaveFailure.simulated }
        )
        writer.onPersistenceFailure = { [recorder] in recorder.failures.append($0) }

        #expect(!writer.delete(id: item.id))
        #expect(recorder.failures == ["删除条目"])
        #expect(recorder.events.isEmpty)

        let rows = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(rows.map(\.id) == [item.id])
    }

    @Test("设置别名：归一化落库、广播原位刷新、不改排序键")
    func setAliasPersistsWithoutReordering() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = ClipboardItem(kind: .text, text: "名字难记")
        item.refreshTitleSnapshot()
        item.refreshContentKey()
        context.insert(item)
        try context.save()

        let events = ClipboardHistoryEventBus()
        let recorder = Recorder()
        events.observe { [recorder] in recorder.events.append($0) }
        let writer = ClipboardHistoryWriter(container: container, events: events)

        let originalRecency = item.recencyID
        #expect(writer.setAlias(id: item.id, alias: "  工作\n邮箱  "))
        #expect(item.alias == "工作 邮箱")
        #expect(item.recencyID == originalRecency, "设置别名不该改变排序")
        #expect(recorder.events == [.rowUpdated(id: item.id)])

        #expect(writer.setAlias(id: item.id, alias: "   "))
        #expect(item.alias == nil)
        #expect(recorder.events.last == .rowUpdated(id: item.id))
    }

    @Test("bookmark 回写失败：只记日志，不上报保存失败")
    func refreshFailureIsSilent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = ClipboardItem(kind: .file, filePath: "/tmp/sixone-silent.txt")
        item.securityScopeBookmark = Data([0])
        context.insert(item)
        try context.save()

        let recorder = Recorder()
        let writer = ClipboardHistoryWriter(
            container: container,
            events: ClipboardHistoryEventBus(),
            persist: { throw SaveFailure.simulated }
        )
        writer.onPersistenceFailure = { [recorder] in recorder.failures.append($0) }

        #expect(!writer.refreshSecurityScopeBookmarks(
            id: item.id,
            [RefreshedBookmark(pathKey: nil, data: Data([1]))]
        ))
        #expect(recorder.failures.isEmpty)
    }

    @Test("bookmark 回写：同一路径每会话只落一次")
    func refreshHappensOncePerSession() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = ClipboardItem(kind: .file, filePath: "/tmp/sixone-once.txt")
        item.securityScopeBookmark = Data([0])
        context.insert(item)
        try context.save()
        let writer = ClipboardHistoryWriter(container: container, events: ClipboardHistoryEventBus())

        #expect(writer.refreshSecurityScopeBookmarks(
            id: item.id,
            [RefreshedBookmark(pathKey: nil, data: Data([1]))]
        ))
        #expect(item.securityScopeBookmark == Data([1]))

        #expect(writer.refreshSecurityScopeBookmarks(
            id: item.id,
            [RefreshedBookmark(pathKey: nil, data: Data([2]))]
        ))
        #expect(item.securityScopeBookmark == Data([1]))
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ClipboardItem.self, ClipboardCollection.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private final class Recorder {
        var events: [ClipboardHistoryEvent] = []
        var failures: [String] = []
    }

    private enum SaveFailure: Error {
        case simulated
    }
}
