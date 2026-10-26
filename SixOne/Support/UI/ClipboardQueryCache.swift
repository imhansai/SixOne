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
    init() {
        urls.countLimit = 400
        fileKinds.countLimit = 2000
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

        var kind: FileKind = .missing
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            kind = isDirectory.boolValue ? .folder : .file
        }

        // 不缓存 missing：文件可能稍后出现，缓存会让行图标一直显示旧判断。
        if kind != .missing {
            fileKinds.setObject(NSNumber(value: kind.rawValue), forKey: key)
        }
        return kind
    }
}
