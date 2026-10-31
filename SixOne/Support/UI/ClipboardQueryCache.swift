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
    private let fileKinds = NSCache<NSString, NSNumber>()
    /// 缺失结果短时缓存：文件可能稍后出现，但滚动重绘也不该每次都打文件系统。
    private let missingPaths = NSCache<NSString, NSDate>()
    private let missingTTL: TimeInterval
    private let now: () -> Date

    init(missingTTL: TimeInterval = 2, now: @escaping () -> Date = { Date() }) {
        self.missingTTL = missingTTL
        self.now = now
        urls.countLimit = 400
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
