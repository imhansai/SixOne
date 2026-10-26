//
//  ClipboardPreviewCache.swift
//  SixOne
//  列表行图片与系统图标缓存，避免 NSImage 重复解码；主线程使用。

import AppKit

final class ClipboardPreviewCache {
    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 600
    }

    func image(for key: String, loader: () -> NSImage?) -> NSImage? {
        let cacheKey = key as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let image = loader() else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    func remove(for key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}
