//
//  StorageBudgetTests.swift
//  SixOneTests
//  外部存储预算：只删能真正释放磁盘的条目，且永远保留最新一条。
//

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("外部存储预算")
@MainActor
struct StorageBudgetTests {
    @Test("外部存储目录由库文件名推导")
    func externalDirectoryPath() {
        let url = ExternalStorageDirectory.url(
            forStoreAt: URL(fileURLWithPath: "/tmp/sixone/SixOne.store")
        )
        #expect(url.path == "/tmp/sixone/.SixOne_SUPPORT/_EXTERNAL_DATA")
    }

    @Test("未超预算：不删条目、不广播")
    func keepsEverythingUnderBudget() async throws {
        let fixture = try BudgetFixture(imageCount: 20, textCount: 0, byteBudget: 20_000)

        await fixture.writer.trimToExternalStorageBudget()

        #expect(fixture.remainingCount == 20)
        #expect(fixture.recorder.events.isEmpty)
    }

    @Test("超预算：从最旧的外部存储条目开始删，最新一条永远保留")
    func trimsOldestFirstAndKeepsNewest() async throws {
        let fixture = try BudgetFixture(imageCount: 200, textCount: 0, byteBudget: 10_000)

        await fixture.writer.trimToExternalStorageBudget()

        // 每条 100 字节：删两批 50 条后正好落到预算内。
        #expect(fixture.remainingCount == 100)
        #expect(fixture.contains(id: fixture.newestID))
        #expect(fixture.recorder.events == [.trimmed])
    }

    @Test("只删外部存储条目：纯文本历史不受影响")
    func leavesTextOnlyRowsAlone() async throws {
        let fixture = try BudgetFixture(imageCount: 10, textCount: 10, byteBudget: 0)

        await fixture.writer.trimToExternalStorageBudget()

        #expect(fixture.imageCount == 0)
        #expect(fixture.textCount == 10)
    }

    @Test("最新一条本身超预算：不删它，只清掉更旧的")
    func neverDeletesNewestEvenWhenOverBudget() async throws {
        let fixture = try BudgetFixture(imageCount: 5, textCount: 0, byteBudget: 0)

        await fixture.writer.trimToExternalStorageBudget()

        #expect(fixture.remainingCount == 1)
        #expect(fixture.contains(id: fixture.newestID))
    }

    @Test("设为无限时不裁剪")
    func unlimitedBudgetKeepsEverything() async throws {
        let fixture = try BudgetFixture(imageCount: 5, textCount: 0, byteBudget: nil)

        await fixture.writer.trimToExternalStorageBudget()

        #expect(fixture.remainingCount == 5)
        #expect(fixture.recorder.events.isEmpty)
    }
}

@MainActor
private struct BudgetFixture {
    let container: ModelContainer
    let context: ModelContext
    let recorder: EventRecorder
    let writer: ClipboardHistoryWriter
    let newestID: UUID

    init(imageCount: Int, textCount: Int, byteBudget: Int64?) throws {
        let schema = Schema([ClipboardItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let events = ClipboardHistoryEventBus()
        let recorder = EventRecorder()
        events.observe { [recorder] event in recorder.record(event) }

        var newestID = UUID()
        for index in 0..<imageCount {
            let item = ClipboardItem(kind: .image, imageData: Data([UInt8(index % 256)]))
            context.insert(item)
            newestID = item.id
        }
        for index in 0..<textCount {
            let item = ClipboardItem(kind: .text, text: "text \(index)")
            context.insert(item)
            newestID = item.id
        }
        try context.save()

        self.container = container
        self.context = context
        self.recorder = recorder
        self.newestID = newestID
        self.writer = ClipboardHistoryWriter(
            container: container,
            events: events,
            retentionInterval: { nil },
            externalByteCount: {
                // 每条外部存储条目按 100 字节计，便于断言批次行为。
                let count = (try? context.fetchCount(FetchDescriptor<ClipboardItem>(
                    predicate: #Predicate { $0.imageData != nil || $0.attributedTextData != nil }
                ))) ?? 0
                return Int64(count) * 100
            },
            externalByteBudget: { byteBudget }
        )
    }

    var remainingCount: Int {
        (try? context.fetchCount(FetchDescriptor<ClipboardItem>())) ?? 0
    }

    var imageCount: Int {
        (try? context.fetchCount(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.imageData != nil }
        ))) ?? 0
    }

    var textCount: Int {
        (try? context.fetchCount(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.kindRaw == "text" }
        ))) ?? 0
    }

    func contains(id: UUID) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == id }
        ))) ?? 0) > 0
    }
}
