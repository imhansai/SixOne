//
//  DateFormatting.swift
//  SixOne

import Foundation

extension Date {
    /// 绝对日期时间，跟随运行时语言。
    var formattedAbsolute: String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(RuntimeLanguage.shared.locale))
    }
}
