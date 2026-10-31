//
//  SettingsStore.swift
//  SixOne

import Foundation
import Observation
import os

enum HistoryRetention: Int, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
    case unlimited

    var id: Int { rawValue }

    var interval: TimeInterval? {
        let day: TimeInterval = 24 * 3600
        switch self {
        case .oneMonth: return 30 * day
        case .threeMonths: return 3 * 30 * day
        case .sixMonths: return 6 * 30 * day
        case .oneYear: return 12 * 30 * day
        case .unlimited: return nil
        }
    }
}

struct IgnoredApplication: Codable, Identifiable, Hashable {
    let bundleIdentifier: String
    let path: String

    private let storedDisplayName: String

    /// 存储键沿用 displayName，改掉会让已保存的列表解码失败。
    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case path
        case storedDisplayName = "displayName"
    }

    init(bundleIdentifier: String, displayName: String, path: String) {
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.storedDisplayName = displayName
    }

    var id: String { bundleIdentifier }

    /// 展示名按当前界面语言实时解析，避免固化首次运行语言。
    var displayName: String {
        let key = "\(path)#\(RuntimeLanguage.shared.current.rawValue)" as NSString
        if let cached = Self.displayNameCache.object(forKey: key) {
            return cached as String
        }
        let resolved = Self.localizedDisplayName(at: URL(fileURLWithPath: path)) ?? storedDisplayName
        Self.displayNameCache.setObject(resolved as NSString, forKey: key)
        return resolved
    }

    static func localizedDisplayName(at url: URL) -> String? {
        guard let bundle = Bundle(url: url) else { return nil }
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = bundle.localizedInfoDictionary?[key] as? String, !name.isEmpty {
                return name
            }
            if let name = bundle.infoDictionary?[key] as? String, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private static let displayNameCache = NSCache<NSString, NSString>()
}

@Observable
final class SettingsStore {
    private static let logger = AppLog.logger("Settings")
    static let defaultRetention = Preferences.defaultRetention

    private static let defaultIgnoredApps: [IgnoredApplication] = [
        IgnoredApplication(
            bundleIdentifier: "com.apple.Passwords",
            displayName: Localizer.string("Passwords"),
            path: "/System/Applications/Passwords.app"
        ),
        IgnoredApplication(
            bundleIdentifier: "com.apple.keychainaccess",
            displayName: Localizer.string("Keychain Access"),
            path: "/System/Library/CoreServices/Applications/Keychain Access.app"
        ),
    ]

    private let preferences: Preferences

    /// 保留时长；相等赋值不算改动（滑块拖动会连续写入同档位）。
    var historyRetention: HistoryRetention {
        didSet {
            guard historyRetention != oldValue else { return }
            preferences.historyRetention = historyRetention
            notifyRetentionChange()
        }
    }

    private var retentionObservers: [(HistoryRetention) -> Void] = []

    /// 订阅保留时长变化；闭包按约定持弱引用，随装配图同生共死。
    func observeRetentionChanges(_ handler: @escaping (HistoryRetention) -> Void) {
        retentionObservers.append(handler)
    }

    /// 语言偏好；重启后生效。
    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            preferences.language = language
        }
    }

    var ignoredApps: [IgnoredApplication] {
        didSet {
            guard ignoredApps != oldValue else { return }
            persistIgnoredApps()
        }
    }

    convenience init(storage: SettingsStorage = UserDefaults.standard) {
        self.init(preferences: Preferences(storage: storage))
    }

    init(preferences: Preferences) {
        self.preferences = preferences
        historyRetention = preferences.historyRetention
        language = preferences.language
        ignoredApps = Self.loadIgnoredApps(from: preferences)
    }

    private static func loadIgnoredApps(from preferences: Preferences) -> [IgnoredApplication] {
        guard let data = preferences.ignoredAppsData else {
            // 无数据 = 首次运行，用默认项，不记日志。
            return Self.defaultIgnoredApps
        }
        do {
            return try JSONDecoder().decode([IgnoredApplication].self, from: data)
        } catch {
            // 解码失败会把用户列表悄悄换回默认项，必须留日志。
            logger.error("忽略列表解码失败，回退默认项：\(error.localizedDescription, privacy: .public)")
            return Self.defaultIgnoredApps
        }
    }

    private func notifyRetentionChange() {
        for observer in retentionObservers { observer(historyRetention) }
    }

    private func persistIgnoredApps() {
        do {
            let data = try JSONEncoder().encode(ignoredApps)
            preferences.ignoredAppsData = data
        } catch {
            Self.logger.error("忽略列表写入失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func restoreDefaultIgnoredApps() {
        ignoredApps = Self.defaultIgnoredApps
    }
}
