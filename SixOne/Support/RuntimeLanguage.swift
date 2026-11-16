//
//  RuntimeLanguage.swift
//  SixOne

import Foundation

/// 当前进程实际生效的语言：由 macOS（含按 App 语言设置）在启动时解析。
/// 旧版本写入的 `AppleLanguages` 保留，升级后语言不跳变。
final class RuntimeLanguage {
    static let shared = RuntimeLanguage()

    let current: AppLanguage

    /// 格式用 locale：macOS 会把按 App 语言与系统地区合成（如 en_CN）。
    var locale: Locale { .autoupdatingCurrent }

    private init() {
        current = AppLanguage.resolved(from: Bundle.main.preferredLocalizations)
    }
}
