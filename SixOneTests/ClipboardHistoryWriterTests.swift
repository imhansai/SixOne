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
            retentionInterval: { nil },
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
            retentionInterval: { nil },
            persist: { throw SaveFailure.simulated }
        )
        writer.onPersistenceFailure = { [recorder] in recorder.failures.append($0) }

        #expect(!writer.delete(id: item.id))
        #expect(recorder.failures == ["删除条目"])
        #expect(recorder.events.isEmpty)

        let rows = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(rows.map(\.id) == [item.id])
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ClipboardItem.self])
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
