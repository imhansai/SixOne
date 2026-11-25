//
//  ClipboardHistoryQuery.swift
//  SixOne
//
//  历史读取条件：搜索词 + 筛选（分组 / 类型 / 来源 / 日期）；值类型便于列表比较迟到结果。
//

import Foundation

/// 最近活动时间区间；按本地自然日切分，与列表里「今天 / 昨天」的理解一致。
nonisolated enum HistoryDateRange: String, CaseIterable, Hashable, Sendable {
    case today
    case yesterday
    case last7Days
    case last30Days
    case older

    /// 左闭右开区间；「至今」用 `.distantFuture` 表示。
    func bounds(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)
            ?? startOfToday
        let startOf7Days = calendar.date(byAdding: .day, value: -6, to: startOfToday)
            ?? startOfToday
        let startOf30Days = calendar.date(byAdding: .day, value: -29, to: startOfToday)
            ?? startOfToday
        switch self {
        case .today:
            return (startOfToday, .distantFuture)
        case .yesterday:
            return (startOfYesterday, startOfToday)
        case .last7Days:
            return (startOf7Days, .distantFuture)
        case .last30Days:
            return (startOf30Days, .distantFuture)
        case .older:
            return (.distantPast, startOf30Days)
        }
    }
}

/// 历史列表的全部筛选维度；区内取并集、维度之间取交集，空集合表示该维度不过滤。
nonisolated struct HistoryFilter: Hashable, Sendable {
    var collections: Set<UUID> = []
    var kinds: Set<ClipboardItemKind> = []
    var sourceApps: Set<String> = []
    var dateRanges: Set<HistoryDateRange> = []

    static let none = HistoryFilter()

    var isActive: Bool { self != .none }

    /// 只有分组筛选；空态文案据此区分「组是空的」与「没有符合筛选的内容」。
    var isCollectionOnly: Bool {
        !collections.isEmpty && kinds.isEmpty && sourceApps.isEmpty && dateRanges.isEmpty
    }

    func toggled(kind: ClipboardItemKind) -> HistoryFilter {
        var copy = self
        if copy.kinds.contains(kind) {
            copy.kinds.remove(kind)
        } else {
            copy.kinds.insert(kind)
        }
        return copy
    }

    func toggled(sourceApp: String) -> HistoryFilter {
        var copy = self
        if copy.sourceApps.contains(sourceApp) {
            copy.sourceApps.remove(sourceApp)
        } else {
            copy.sourceApps.insert(sourceApp)
        }
        return copy
    }

    func toggled(dateRange: HistoryDateRange) -> HistoryFilter {
        var copy = self
        if copy.dateRanges.contains(dateRange) {
            copy.dateRanges.remove(dateRange)
        } else {
            copy.dateRanges.insert(dateRange)
        }
        return copy
    }

    func toggled(collectionID: UUID) -> HistoryFilter {
        var copy = self
        if copy.collections.contains(collectionID) {
            copy.collections.remove(collectionID)
        } else {
            copy.collections.insert(collectionID)
        }
        return copy
    }

    /// 条目是否命中筛选（不含搜索词）；列表增量更新与仓库校验共用。
    func matches(
        kind: ClipboardItemKind,
        collectionID: UUID?,
        sourceAppBundleIdentifier: String?,
        lastActivityAt: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if !collections.isEmpty {
            guard let collectionID, collections.contains(collectionID) else { return false }
        }
        if !kinds.isEmpty, !kinds.contains(kind) {
            return false
        }
        if !sourceApps.isEmpty {
            guard let sourceAppBundleIdentifier,
                  sourceApps.contains(sourceAppBundleIdentifier)
            else { return false }
        }
        if !dateRanges.isEmpty {
            let inRange = dateRanges.contains { range in
                let bounds = range.bounds(now: now, calendar: calendar)
                return lastActivityAt >= bounds.start && lastActivityAt < bounds.end
            }
            guard inRange else { return false }
        }
        return true
    }

    /// 收起期间有新复制：放弃筛选，保证新条目可见；否则保留上次筛选。
    func restoredOnShow(hasNewContent: Bool) -> HistoryFilter {
        hasNewContent ? .none : self
    }
}

nonisolated struct HistoryQuery: Hashable, Sendable {
    var text: String
    var filter: HistoryFilter

    init(text: String = "", filter: HistoryFilter = .none) {
        self.text = text
        self.filter = filter
    }
}
