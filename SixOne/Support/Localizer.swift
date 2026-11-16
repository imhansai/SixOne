//
//  Localizer.swift
//  SixOne

import Foundation

/// 按进程当前语言解析本地化字符串；语言由 macOS 在启动时选定。
enum Localizer {
    static func string(_ key: String.LocalizationValue, table: String? = nil) -> String {
        String(localized: key, table: table)
    }

    static func groupTitle(firstName: String, count: Int) -> String {
        let remaining = max(count - 1, 0)
        if remaining == 1 {
            return String(format: Localizer.string("%@ and the other item"), firstName)
        }
        return String(
            format: Localizer.string("%@ and the other %@ items"),
            firstName,
            String(remaining)
        )
    }
}
