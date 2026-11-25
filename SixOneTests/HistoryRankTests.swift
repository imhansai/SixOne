//
//  HistoryRankTests.swift
//  SixOneTests
//  清空搜索后的窗口名次：按更新行数统计、沿用筛选口径，数到上限即停。
//

import Foundation
import Testing
@testable import SixOne

@Suite("历史定位名次")
@MainActor
struct HistoryRankTests {
    @Test("名次统计比该行更新且命中筛选的条目数")
    func ranksNewerRowsUnderFilter() throws {
        let harness = try ClipboardHarness()
        let context = harness.context

        let oldest = ClipboardItem(kind: .text, text: "最旧")
        context.insert(oldest)
        let middle = ClipboardItem(kind: .text, text: "中间")
        context.insert(middle)
        let image = ClipboardItem(kind: .image, imageData: Data([0x01]), contentType: "PNG")
        context.insert(image)
        let newest = ClipboardItem(kind: .text, text: "最新")
        context.insert(newest)
        try context.save()

        #expect(harness.manager.historyRank(ofRowWith: oldest.recencyID, filter: .none, upTo: 100) == 3)
        #expect(harness.manager.historyRank(ofRowWith: middle.recencyID, filter: .none, upTo: 100) == 2)
        #expect(harness.manager.historyRank(ofRowWith: newest.recencyID, filter: .none, upTo: 100) == 0)

        // 与列表同口径：只看类型时，图片不参与文本行的名次。
        let textOnly = HistoryFilter(kinds: [.text])
        #expect(harness.manager.historyRank(ofRowWith: oldest.recencyID, filter: textOnly, upTo: 100) == 2)
        #expect(harness.manager.historyRank(ofRowWith: image.recencyID, filter: textOnly, upTo: 100) == 1)
    }

    @Test("名次数到上限就停：菜单只关心是否小于窗口容量")
    func rankStopsAtLimit() throws {
        let harness = try ClipboardHarness()
        let context = harness.context
        let oldest = ClipboardItem(kind: .text, text: "最旧")
        context.insert(oldest)
        for index in 0..<3 {
            context.insert(ClipboardItem(kind: .text, text: "较新 \(index)"))
        }
        try context.save()

        #expect(
            harness.manager.historyRank(ofRowWith: oldest.recencyID, filter: .none, upTo: 2) == 2
        )
        #expect(
            harness.manager.historyRank(ofRowWith: oldest.recencyID, filter: .none, upTo: 10) == 3
        )
    }

    @Test("分组筛选只统计同组内更新的条目")
    func rankHonorsCollectionFilter() throws {
        let harness = try ClipboardHarness()
        let context = harness.context
        let group = UUID()

        let grouped = ClipboardItem(kind: .text, text: "组内较早", collectionID: group)
        context.insert(grouped)
        let ungrouped = ClipboardItem(kind: .text, text: "未分组较新")
        context.insert(ungrouped)
        let groupedNewest = ClipboardItem(kind: .text, text: "组内最新", collectionID: group)
        context.insert(groupedNewest)
        try context.save()

        #expect(
            harness.manager.historyRank(
                ofRowWith: grouped.recencyID,
                filter: HistoryFilter(collections: [group]),
                upTo: 100
            ) == 1
        )
    }
}
