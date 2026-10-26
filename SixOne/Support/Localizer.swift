//
//  Localizer.swift
//  SixOne

import Foundation

/// 按运行时语言解析本地化字符串，切换后立即生效。
enum Localizer {
    static func string(_ key: String.LocalizationValue, table: String? = nil) -> String {
        var resource = LocalizedStringResource(key, table: table)
        resource.locale = RuntimeLanguage.shared.locale
        return String(localized: resource)
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
