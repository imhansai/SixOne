//
//  AppLanguage.swift
//  SixOne
//  应用支持的界面语言；最终语言由 macOS（含按 App 语言设置）在启动时解析。
//

import Foundation

enum AppLanguage: String {
    case english
    case simplifiedChinese = "zh-Hans"

    /// 取 Bundle 解析出的本地化里第一个受支持的语言；其余一律回落开发语言。
    static func resolved(from localizations: [String]) -> AppLanguage {
        for localization in localizations {
            switch localization {
            case "en": return .english
            case simplifiedChinese.rawValue: return .simplifiedChinese
            default: continue
            }
        }
        return .english
    }
}
