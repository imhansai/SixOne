//
//  DateFormatting.swift
//  SixOne

import Foundation

extension Date {
    /// 预览元数据用固定时间戳：2026-11-11 17:34:15。
    var formattedTimestamp: String {
        Self.previewTimestampFormatter.string(from: self)
    }

    private static let previewTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
