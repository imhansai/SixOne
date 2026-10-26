//
//  PreviewImageDecoder.swift
//  SixOne
//  图片预览解码：后台完成解码、EXIF 转正与降采样，输出像素已就绪的位图。

import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// 不用 `NSImage(data:)`：像素解码会推迟到主线程首次绘制，造成优先级反转。
/// 同源各档 `displaySize` 相同，换档不改变视图拟合尺寸。
nonisolated enum PreviewImageDecoder {
    struct Tier: Sendable {
        let bitmap: CGImage
        /// 显示尺寸（点），同源所有档位共用。
        let displaySize: NSSize
        let sourcePixelSize: NSSize
        /// 真实像素长边；`NSImage` 的 representations 报的是点尺寸，不能用于判断清晰度。
        var pixelSize: Int { max(bitmap.width, bitmap.height) }
    }

    static func decode(_ data: Data, maxPixelSize: Int) async -> Tier? {
        await offMain {
            guard let source = makeSource(data: data) else { return nil }
            return tier(from: source, maxPixelSize: maxPixelSize)
        }
    }

    static func decode(contentsOf url: URL, maxPixelSize: Int) async -> Tier? {
        await offMain {
            guard let source = makeSource(url: url) else { return nil }
            return tier(from: source, maxPixelSize: maxPixelSize)
        }
    }

    // MARK: - 内部

    /// 解码放后台；QoS 用 `.default`，避免 ImageIO 内部线程触发优先级反转。
    private static func offMain(_ work: @escaping @Sendable () -> Tier?) async -> Tier? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .default).async {
                continuation.resume(returning: work())
            }
        }
    }

    private static func makeSource(data: Data) -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    private static func makeSource(url: URL) -> CGImageSource? {
        CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    private static func tier(from source: CGImageSource, maxPixelSize: Int) -> Tier? {
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            // 不加会返回内嵌的小缩略图（常见 160×120）。
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // 不加 EXIF 旋转不会落到像素。
            kCGImageSourceCreateThumbnailWithTransform: true,
            // 立即解码，别拖到首次绘制。
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let fallback = NSSize(width: bitmap.width, height: bitmap.height)
        let metrics = metrics(of: source) ?? (display: fallback, pixels: fallback)
        return Tier(bitmap: bitmap, displaySize: metrics.display, sourcePixelSize: metrics.pixels)
    }

    private static func metrics(of source: CGImageSource) -> (display: NSSize, pixels: NSSize)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = number(properties[kCGImagePropertyPixelWidth]), pixelWidth > 0,
              let pixelHeight = number(properties[kCGImagePropertyPixelHeight]), pixelHeight > 0
        else { return nil }

        let rotated = (5...8).contains(Int(number(properties[kCGImagePropertyOrientation]) ?? 1))
        let pixels = rotated
            ? NSSize(width: pixelHeight, height: pixelWidth)
            : NSSize(width: pixelWidth, height: pixelHeight)

        let dpiWidth = number(properties[kCGImagePropertyDPIWidth]) ?? 72
        let dpiHeight = number(properties[kCGImagePropertyDPIHeight]) ?? 72
        let (widthDPI, heightDPI) = rotated ? (dpiHeight, dpiWidth) : (dpiWidth, dpiHeight)
        let display = NSSize(
            width: pixels.width * (widthDPI > 0 ? 72 / widthDPI : 1),
            height: pixels.height * (heightDPI > 0 ? 72 / heightDPI : 1)
        )
        return (display, pixels)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
