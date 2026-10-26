//
//  ClipboardTimeCache.swift
//  SixOne
//  列表副标题时间文案缓存；键含时间与语言，避免置顶或切语言后显示旧文案。

import Foundation

final class ClipboardTimeCache {
    private let cache = NSCache<NSString, NSString>()

    init() {
        cache.countLimit = 2000
    }

    private func cacheKey(for id: UUID, lastActivityAt: Date) -> NSString {
        let lang = RuntimeLanguage.shared.languageCode ?? "system"
        let locale = RuntimeLanguage.shared.locale.identifier
        let time = lastActivityAt.timeIntervalSinceReferenceDate
        // 跨过午夜后「今天/昨天」会变，键里带上日状态与当前时区。
        let calendar = Calendar.current
        let dayState: String
        if calendar.isDateInToday(lastActivityAt) {
            dayState = "today"
        } else if calendar.isDateInYesterday(lastActivityAt) {
            dayState = "yesterday"
        } else {
            dayState = "older"
        }
        return "\(id.uuidString)-\(time)-\(lang)-\(locale)-\(TimeZone.current.identifier)-\(dayState)" as NSString
    }

    func copyTime(for id: UUID, lastActivityAt: Date, locale: Locale) -> String {
        let key = cacheKey(for: id, lastActivityAt: lastActivityAt)
        if let cached = cache.object(forKey: key) {
            return cached as String
        }

        let text = Self.copyTimeText(for: lastActivityAt, locale: locale)
        cache.setObject(text as NSString, forKey: key)
        return text
    }

    private static func copyTimeText(for date: Date, locale: Locale) -> String {
        let calendar = Calendar.current
        let timeStyle = Date.FormatStyle(locale: locale)
        if calendar.isDateInToday(date) {
            return date.formatted(timeStyle.hour().minute())
        } else if calendar.isDateInYesterday(date) {
            let time = date.formatted(timeStyle.hour().minute())
            return String(localized: "Yesterday \(time)", locale: locale)
        }
        return date.formatted(timeStyle.month().day().hour().minute())
    }
}
