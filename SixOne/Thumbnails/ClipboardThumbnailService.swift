//
//  ClipboardThumbnailService.swift
//  SixOne
//
//  缩略图生成：Quick Look 取图 + ImageIO 编码。纯计算、不碰库，
//  可在后台线程调用（`nonisolated`），由调用方决定何时写回条目。
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

nonisolated enum ClipboardThumbnailService {
    /// sRGB 颜色空间（构造不应失败，只解包一次）。
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// 列表行缩略图的目标边长（像素）；列表显示 40pt，128 覆盖 2×/3× 屏。
    static let listThumbnailPixelSize: CGFloat = 128

    /// 缩略图来源。Quick Look 只能按 URL 取图，所以剪贴板位图会先落一份临时文件；
    /// 颜色没有文件、没有位图，直接画一个纯色块。
    enum Source {
        case file(path: String, bookmark: Data?)
        case bitmap(Data)
        case color(Data)
    }

    /// 取图并编码：`thumbnailData` 是持久化列，只能存 Data。
    static func makeThumbnail(
        from source: Source,
        pixelSize: CGFloat = listThumbnailPixelSize
    ) async -> Data? {
        let image: CGImage?
        switch source {
        case let .file(path, bookmark):
            image = await quickLookImage(at: URL(fileURLWithPath: path), bookmark: bookmark, size: pixelSize)
        case let .bitmap(data):
            image = await quickLookImage(atTemporaryCopyOf: data, pixelSize: pixelSize)
        case let .color(data):
            image = swatchImage(ofColorData: data, size: pixelSize)
        }
        guard let image else { return nil }
        // HEIC 优先：体积远小于 PNG，且保留 iconMode 装饰的透明留白与投影
        // （JPEG 没有 alpha 通道，会把透明区填成实色）；不可用时退回 PNG。
        return encode(image, as: .heic, quality: 0.8) ?? encode(image, as: .png)
    }

    /// 颜色条目的纯色缩略图：解出 sRGB 颜色后填满一个方块，透明底交由上层自行合成。
    /// 与其它缩略图同尺寸，走同一条 HEIC/PNG 编码。
    private static func swatchImage(
        ofColorData data: Data,
        size: CGFloat = listThumbnailPixelSize,
        scale: CGFloat = 1
    ) -> CGImage? {
        guard let rgb = PasteboardFormat.color(from: data)?.usingColorSpace(.sRGB) else { return nil }
        let pixels = Int(size * scale)
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context.setFillColor(rgb.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }

    /// 沙盒下先用捕获时固化的 bookmark 恢复文件访问权，失败再试原始路径。
    static func quickLookImage(
        at url: URL,
        bookmark: Data?,
        size: CGFloat = 256,
        scale: CGFloat = 1
    ) async -> CGImage? {
        if let bookmark, let scoped = SecurityScopedFileAccess.startAccess(bookmark: bookmark) {
            defer { scoped.stopAccessingSecurityScopedResource() }
            if let image = await quickLookImage(at: scoped, size: size, scale: scale) { return image }
        }
        return await quickLookImage(at: url, size: size, scale: scale)
    }

    /// Quick Look 取图。`iconMode` 让系统按文件图标的方式装饰缩略图（页面、卷角、圆角、
    /// 投影），各类条目因此与系统文件图标同族；`.icon` 兜住没有内容预览的文件
    /// （压缩包、文件夹、App），有内容预览时仍返回内容缩略图。
    /// `size` 是点、`scale` 是屏倍率（实际位图 = size × scale）；列表行缩略图与文件组预览共用本方法。
    static func quickLookImage(
        at url: URL,
        size: CGFloat = 256,
        scale: CGFloat = 1
    ) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: [.thumbnail, .icon]
        )
        request.iconMode = true
        // 只把 CGImage 交回 continuation：QLThumbnailRepresentation 不是 Sendable。
        let image = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                continuation.resume(returning: thumbnail?.cgImage)
            }
        }
        return image
    }

    /// 剪贴板位图落成临时文件（扩展名取数据自身类型，粘贴板里是 PNG 或 TIFF），
    /// 交给同一个 Quick Look 请求，用完即删。
    private static func quickLookImage(atTemporaryCopyOf data: Data, pixelSize: CGFloat) async -> CGImage? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixone-thumbnail-\(UUID().uuidString).\(PasteboardFormat.fileExtension(ofBitmap: data))")
        guard (try? data.write(to: url)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        return await quickLookImage(at: url, size: pixelSize)
    }

    /// ImageIO 编码：不缩放（尺寸由取图环节决定），`quality` 仅对有损格式生效。
    static func encode(_ image: CGImage, as type: UTType, quality: CGFloat? = nil) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: CFDictionary? = quality.map {
            [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary
        }
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
