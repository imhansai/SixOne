//
//  HistoryFilterTests.swift
//  SixOneTests
//  筛选值类型：多选开合、日期边界与条目命中规则。
//

import Foundation
import Testing
@testable import SixOne

@Suite("历史筛选")
struct HistoryFilterTests {
    @Test("类型与来源可多选，再点同一项取消")
    func multiSelectToggles() {
        var filter = HistoryFilter.none
        #expect(!filter.isActive)

        filter = filter.toggled(kind: .image)
        filter = filter.toggled(kind: .file)
        #expect(filter.kinds == [.image, .file])
        #expect(filter.isActive)

        filter = filter.toggled(kind: .image)
        #expect(filter.kinds == [.file])

        filter = filter.toggled(sourceApp: "com.apple.Safari")
        filter = filter.toggled(sourceApp: "com.apple.Notes")
        #expect(filter.sourceApps == ["com.apple.Safari", "com.apple.Notes"])

        filter = filter.toggled(sourceApp: "com.apple.Safari")
        #expect(filter.sourceApps == ["com.apple.Notes"])

        filter = filter.toggled(kind: .file)
        filter = filter.toggled(sourceApp: "com.apple.Notes")
        #expect(filter == .none, "全部取消后回到不筛选")
    }

    @Test("日期可多选：再点同一区间取消")
    func dateRangesAreMultiSelect() {
        var filter = HistoryFilter.none
        filter = filter.toggled(dateRange: .today)
        #expect(filter.dateRanges == [.today])

        filter = filter.toggled(dateRange: .last30Days)
        #expect(filter.dateRanges == [.today, .last30Days])

        filter = filter.toggled(dateRange: .today)
        #expect(filter.dateRanges == [.last30Days])

        filter = filter.toggled(dateRange: .last30Days)
        #expect(filter.dateRanges.isEmpty)
        #expect(!filter.isActive)
    }

    @Test("分组可多选：开合不影响其它维度")
    func collectionToggleKeepsOtherDimensions() {
        let first = UUID()
        let second = UUID()
        var filter = HistoryFilter(kinds: [.image], sourceApps: ["com.apple.Safari"])

        filter = filter.toggled(collectionID: first)
        #expect(filter.collections == [first])
        #expect(filter.kinds == [.image])
        #expect(filter.sourceApps == ["com.apple.Safari"])

        filter = filter.toggled(collectionID: second)
        #expect(filter.collections == [first, second])

        filter = filter.toggled(collectionID: first)
        #expect(filter.collections == [second])
        #expect(filter.kinds == [.image])
    }

    @Test("只有分组筛选时单独标记，供空态文案区分")
    func collectionOnly() {
        let id = UUID()
        #expect(HistoryFilter(collections: [id]).isCollectionOnly)
        #expect(!HistoryFilter(collections: [id], kinds: [.text]).isCollectionOnly)
        #expect(!HistoryFilter.none.isCollectionOnly)
    }

    @Test("日期区间按本地自然日切分，今天与昨天不重叠")
    func dateBoundsUseCalendarDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 10))
        )

        let today = HistoryDateRange.today.bounds(now: now, calendar: calendar)
        #expect(today.start == calendar.startOfDay(for: now))
        #expect(today.end == .distantFuture)

        let yesterday = HistoryDateRange.yesterday.bounds(now: now, calendar: calendar)
        #expect(yesterday.start == calendar.date(byAdding: .day, value: -1, to: today.start))
        #expect(yesterday.end == today.start)

        let last7 = HistoryDateRange.last7Days.bounds(now: now, calendar: calendar)
        #expect(last7.start == calendar.date(byAdding: .day, value: -6, to: today.start))
        #expect(last7.end == .distantFuture)

        let last30 = HistoryDateRange.last30Days.bounds(now: now, calendar: calendar)
        #expect(last30.start == calendar.date(byAdding: .day, value: -29, to: today.start))
        #expect(last30.end == .distantFuture)

        let older = HistoryDateRange.older.bounds(now: now, calendar: calendar)
        #expect(older.start == .distantPast)
        #expect(older.end == last30.start)
    }

    @Test("条目命中：区间之间 AND，区内取并集")
    func matchesCombinesDimensions() throws {
        let group = UUID()
        let otherGroup = UUID()
        let now = Date()
        let filter = HistoryFilter(
            collections: [group, otherGroup],
            kinds: [.image, .file],
            sourceApps: ["com.apple.Safari"],
            dateRanges: [.today, .last7Days]
        )

        #expect(filter.matches(
            kind: .image,
            collectionID: group,
            sourceAppBundleIdentifier: "com.apple.Safari",
            lastActivityAt: now
        ))
        #expect(filter.matches(
            kind: .file,
            collectionID: otherGroup,
            sourceAppBundleIdentifier: "com.apple.Safari",
            lastActivityAt: now
        ), "任一分组命中即可")
        #expect(!filter.matches(
            kind: .text,
            collectionID: group,
            sourceAppBundleIdentifier: "com.apple.Safari",
            lastActivityAt: now
        ), "类型不在集合里")
        #expect(!filter.matches(
            kind: .image,
            collectionID: UUID(),
            sourceAppBundleIdentifier: "com.apple.Safari",
            lastActivityAt: now
        ), "分组不在集合里")
        #expect(!filter.matches(
            kind: .image,
            collectionID: group,
            sourceAppBundleIdentifier: "com.apple.Notes",
            lastActivityAt: now
        ), "来源不在集合里")
        #expect(!filter.matches(
            kind: .image,
            collectionID: group,
            sourceAppBundleIdentifier: nil,
            lastActivityAt: now
        ), "来源筛选生效时无来源条目不该命中")
        #expect(filter.matches(
            kind: .image,
            collectionID: group,
            sourceAppBundleIdentifier: "com.apple.Safari",
            lastActivityAt: now.addingTimeInterval(-3 * 86_400)
        ), "任一日期区间命中即可")
        #expect(!filter.matches(
            kind: .image,
            collectionID: group,
            sourceAppBundleIdentifier: "com.apple.Safari",
            lastActivityAt: now.addingTimeInterval(-8 * 86_400)
        ), "超出全部日期区间")
    }

    @Test("搜索条件与筛选并存")
    func queryCarriesFilter() {
        let group = UUID()
        let full = HistoryQuery(
            text: "报表",
            filter: HistoryFilter(collections: [group], kinds: [.text])
        )
        #expect(full.filter.collections == [group])
        #expect(full.filter.kinds == [.text])
        #expect(HistoryQuery(text: "报表").filter == .none)
    }
}
