//
//  AppLanguage.swift
//  SixOne
//  界面语言偏好；运行时语言与设置共用语言码。

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// 写入 `AppleLanguages` 的语言码；跟随系统为 nil。
    var languageCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }

    static let storageKey = "appLanguage"
}
