//
//  PreviewImageDecoderTests.swift
//  SixOneTests
//  预览解码：像素上限、EXIF 方向、DPI 与内嵌缩略图；夹具用中等尺寸避免拖慢并行套件。

import AppKit
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SixOne

@Suite("预览图片解码")
@MainActor
struct PreviewImageDecoderTests {
    @Test("长边不超过请求的像素上限")
    func respectsMaxPixelSize() async throws {
        let url = try Self.writePNG(width: 2000, height: 1500)
        defer { try? FileManager.default.removeItem(at: url) }

        let tier = try #require(await PreviewImageDecoder.decode(contentsOf: url, maxPixelSize: 512))
        let longest = max(tier.bitmap.width, tier.bitmap.height)
        #expect(longest <= 512, "解码结果超过了请求的上限")
        #expect(longest >= 500, "长边只有 \(longest)px —— 没有按上限重绘")
    }

    @Test("EXIF 方向落到像素与显示尺寸上")
    func appliesExifOrientation() async throws {
        let url = try Self.writeJPEG(width: 2000, height: 1500, orientation: 6)
        defer { try? FileManager.default.removeItem(at: url) }

        let tier = try #require(await PreviewImageDecoder.decode(contentsOf: url, maxPixelSize: 1024))
        #expect(tier.displaySize.height > tier.displaySize.width, "显示尺寸没转正，竖图会显示成横图")
        #expect(tier.bitmap.height > tier.bitmap.width, "位图像素没转正，画出来仍会横着")
        #expect(tier.sourcePixelSize == NSSize(width: 1500, height: 2000), "源图像素没转正")
    }

    @Test("带内嵌缩略图时不会退化成内嵌小图")
    func ignoresEmbeddedThumbnail() async throws {
        let url = try Self.writeJPEG(width: 3000, height: 2000, orientation: nil, embedThumbnail: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))

        // 先确证夹具真带内嵌缩略图，否则用例会变成空断言。
        let embedded = try #require(
            CGImageSourceCreateThumbnailAtIndex(
                source, 0, [kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary
            ),
            "夹具没带内嵌缩略图，这条用例会变成空断言"
        )
        let embeddedLongest = max(embedded.width, embedded.height)
        #expect(embeddedLongest < 1024, "内嵌缩略图 \(embeddedLongest)px 已达上限，夹具失去区分度")

        let tier = try #require(await PreviewImageDecoder.decode(contentsOf: url, maxPixelSize: 1024))
        let longest = max(tier.bitmap.width, tier.bitmap.height)
        #expect(longest > embeddedLongest, "长边 \(longest)px 没超过内嵌缩略图，取到小图了")
        #expect(longest >= 1000, "长边只有 \(longest)px —— 取到内嵌缩略图了")
    }

    @Test("显示尺寸与 NSImage(data:) 一致（换解码路径不改预览拟合尺寸）")
    func displaySizeMatchesLegacyNSImage() async throws {
        let plain = try Self.writePNG(width: 2000, height: 1500)
        defer { try? FileManager.default.removeItem(at: plain) }
        let rotated = try Self.writeJPEG(width: 2000, height: 1500, orientation: 6)
        defer { try? FileManager.default.removeItem(at: rotated) }
        let highDPI = try Self.writePNG(width: 2000, height: 1500, pointSize: NSSize(width: 1000, height: 750))
        defer { try? FileManager.default.removeItem(at: highDPI) }

        for url in [plain, rotated, highDPI] {
            let data = try Data(contentsOf: url)
            let legacy = try #require(NSImage(data: data))
            let tier = try #require(await PreviewImageDecoder.decode(data, maxPixelSize: 1024))
            #expect(
                abs(tier.displaySize.width - legacy.size.width) < 0.01
                    && abs(tier.displaySize.height - legacy.size.height) < 0.01,
                "\(url.lastPathComponent)：新解码 \(tier.displaySize) 与 NSImage 的 \(legacy.size) 不一致"
            )
        }
    }

    // MARK: - 夹具

    private static func writePNG(width: Int, height: Int, pointSize: NSSize? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "sixone-decoder-\(UUID().uuidString).png")
        let rep = try #require(makeBitmap(width: width, height: height))
        if let pointSize { rep.size = pointSize }
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
        return url
    }

    private static func writeJPEG(
        width: Int,
        height: Int,
        orientation: Int?,
        embedThumbnail: Bool = false
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "sixone-decoder-\(UUID().uuidString).jpg")
        let rep = try #require(makeBitmap(width: width, height: height))
        let image = try #require(rep.cgImage)
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        )
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        if embedThumbnail { properties[kCGImageDestinationEmbedThumbnail] = true }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination), "JPEG 夹具写失败")
        return url
    }

    private static func makeBitmap(width: Int, height: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let pixels = rep.bitmapData else { return nil }
        var index = 0
        while index < width * height * 4 {
            pixels[index] = UInt8((index / 4) % 251)
            pixels[index + 1] = UInt8((index / 97) % 241)
            pixels[index + 2] = UInt8((index / 13) % 233)
            pixels[index + 3] = 255
            index += 4
        }
        return rep
    }
}
