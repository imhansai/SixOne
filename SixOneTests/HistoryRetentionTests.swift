//
//  HistoryRetentionTests.swift
//  SixOneTests

import Foundation
import Testing
@testable import SixOne

/// 按保留时长裁剪：启动与改档位都会跑，边界与去重索引都须钉住。
@Suite("按保留时长裁剪")
@MainActor
struct HistoryRetentionTests {
    @Test("保留期内的条目不动")
    func keepsItemsWithinRetention() async throws {
        let harness = try ClipboardHarness(retention: .oneMonth)
        harness.pasteboard.simulateCopy(text: "fresh")
        await harness.pollAndWait()

        harness.manager.trimToRetention()

        #expect(harness.itemsNewestFirst().map(\.text) == ["fresh"])
        #expect(!harness.recorder.events.contains(.trimmed))
    }

    @Test("超出保留期的条目被删除，并释放去重索引")
    func trimsExpiredItemsAndReleasesIndex() async throws {
        let harness = try ClipboardHarness(retention: .oneMonth)
        harness.pasteboard.simulateCopy(text: "old")
        await harness.pollAndWait()
        harness.pasteboard.simulateCopy(text: "recent")
        await harness.pollAndWait()

        let old = try #require(harness.itemsNewestFirst().first { $0.text == "old" })
        old.lastActivityAt = Date().addingTimeInterval(-40 * 24 * 3600)
        try harness.context.save()

        harness.manager.trimToRetention()

        #expect(harness.itemsNewestFirst().map(\.text) == ["recent"])
        #expect(harness.recorder.events.last == .trimmed)

        harness.pasteboard.simulateCopy(text: "old")
        await harness.pollAndWait()
        #expect(harness.itemsNewestFirst().count == 2)
        #expect(harness.recorder.events.last == .inserted(id: harness.itemsNewestFirst()[0].id))
    }

    @Test("无限档位一条都不删")
    func unlimitedRetentionKeepsEverything() async throws {
        let harness = try ClipboardHarness(retention: .unlimited)
        harness.pasteboard.simulateCopy(text: "ancient")
        await harness.pollAndWait()
        let item = try #require(harness.itemsNewestFirst().first)
        item.lastActivityAt = Date().addingTimeInterval(-400 * 24 * 3600)
        try harness.context.save()

        harness.manager.trimToRetention()

        #expect(harness.itemsNewestFirst().count == 1)
        #expect(!harness.recorder.events.contains(.trimmed))
    }

    @Test("启动时就按当前保留时长裁一次")
    func trimsOnLaunch() throws {
        let harness = try ClipboardHarness(retention: .oneMonth) { context in
            let expired = ClipboardItem(kind: .text, text: "left over")
            expired.lastActivityAt = Date().addingTimeInterval(-40 * 24 * 3600)
            context.insert(expired)
            try context.save()
        }

        #expect(harness.itemsNewestFirst().isEmpty)
        #expect(harness.recorder.events == [.trimmed])
    }
}
