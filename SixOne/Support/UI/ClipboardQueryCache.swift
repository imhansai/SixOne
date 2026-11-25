//
//  ClipboardQueryCache.swift
//  SixOne
//  行渲染中的系统查询缓存（应用 URL、路径类型），主线程使用。

import AppKit
import Foundation

final class ClipboardQueryCache {
    enum FileKind: Int {
        case missing
        case file
        case folder
    }

    private let urls = NSCache<NSString, NSURL>()
    private let appNames = NSCache<NSString, NSString>()
    private let fileKinds = NSCache<NSString, NSNumber>()
    /// 缺失结果短时缓存：文件可能稍后出现，但滚动重绘也不该每次都打文件系统。
    private let missingPaths = NSCache<NSString, NSDate>()
    private let missingTTL: TimeInterval
    private let now: () -> Date

    init(missingTTL: TimeInterval = 2, now: @escaping () -> Date = { Date() }) {
        self.missingTTL = missingTTL
        self.now = now
        urls.countLimit = 400
        appNames.countLimit = 200
        fileKinds.countLimit = 2000
        missingPaths.countLimit = 2000
    }

    func appURL(for bundleIdentifier: String) -> URL? {
        let key = bundleIdentifier as NSString
        if let cached = urls.object(forKey: key) {
            return cached as URL
        }

        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        if let url {
            urls.setObject(url as NSURL, forKey: key)
        }
        return url
    }

    /// 应用显示名；查不到 App 时退回 bundle id，至少还能辨认来源。
    func appDisplayName(for bundleIdentifier: String) -> String {
        let key = bundleIdentifier as NSString
        if let cached = appNames.object(forKey: key) {
            return cached as String
        }

        // 查不到 App 时退回 bundle id，但不缓存：App 可能稍后才安装。
        guard let url = appURL(for: bundleIdentifier) else { return bundleIdentifier }
        let name = Self.applicationName(at: url)
        appNames.setObject(name as NSString, forKey: key)
        return name
    }

    /// 优先用 App 自己声明的名字；退回 Finder 显示名时去掉 `.app` 后缀。
    private static func applicationName(at url: URL) -> String {
        if let name = IgnoredApplication.localizedDisplayName(at: url) {
            return name
        }
        let fallback = FileManager.default.displayName(atPath: url.path)
        return fallback.hasSuffix(".app") ? String(fallback.dropLast(4)) : fallback
    }

    func fileKind(atPath path: String) -> FileKind {
        let key = path as NSString
        if let cached = fileKinds.object(forKey: key) {
            return FileKind(rawValue: cached.intValue) ?? .missing
        }
        if let checkedAt = missingPaths.object(forKey: key),
           now().timeIntervalSince(checkedAt as Date) < missingTTL {
            return .missing
        }

        var kind: FileKind = .missing
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            kind = isDirectory.boolValue ? .folder : .file
        }

        if kind == .missing {
            missingPaths.setObject(now() as NSDate, forKey: key)
        } else {
            missingPaths.removeObject(forKey: key)
            fileKinds.setObject(NSNumber(value: kind.rawValue), forKey: key)
        }
        return kind
    }
}
