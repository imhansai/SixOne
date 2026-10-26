//
//  FileGroupThumbnailCache.swift
//  SixOne

import AppKit

/// 缩略图缓存；键含路径、边长、倍率与文件版本，并合并并发请求。
final class FileGroupThumbnailCache {
    private let images = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    init() {
        images.countLimit = 400
    }

    /// 取缩略图；同键请求合并，NSImage 在主线程创建。
    func thumbnail(for url: URL, pointSize: CGFloat, scale: CGFloat, version: Double) async -> NSImage? {
        let key = "group-thumb|\(url.path)|\(Int(pointSize))|\(Int(max(scale, 1) * 100))|\(Int(version))"
        if let cached = images.object(forKey: key as NSString) { return cached }
        let task: Task<CGImage?, Never>
        if let running = inFlight[key] {
            task = running
        } else {
            task = Task { await ClipboardThumbnailService.quickLookImage(at: url, size: pointSize, scale: scale) }
            inFlight[key] = task
        }
        let cgImage = await task.value
        if inFlight[key] == task { inFlight[key] = nil }
        guard let cgImage else { return nil }
        let pixelScale = max(scale, 1)
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: CGFloat(cgImage.width) / pixelScale,
                height: CGFloat(cgImage.height) / pixelScale
            )
        )
        images.setObject(image, forKey: key as NSString)
        return image
    }
}
