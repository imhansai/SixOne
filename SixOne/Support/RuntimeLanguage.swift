//
//  RuntimeLanguage.swift
//  SixOne

import Foundation
import Observation

/// 运行时当前语言的可观察源，供 SwiftUI 与 AppKit/模型层读取。
@Observable
final class RuntimeLanguage {
    static let shared = RuntimeLanguage()

    var current: AppLanguage = .system

    var locale: Locale {
        switch current {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }

    var languageCode: String? {
        current.languageCode
    }

    /// 启动时恢复；须在创建 NSApplication 前调用。
    func restoreFromDefaults() {
        let raw = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
        current = AppLanguage(rawValue: raw ?? "") ?? .system
    }

    /// 写入 AppleLanguages 使本次启动的系统文案切换；.system 时移除覆盖，须在创建 NSApplication 前调用。
    func applyToDefaults() {
        if let code = languageCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}
