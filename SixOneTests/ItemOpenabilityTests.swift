//
//  ItemOpenabilityTests.swift
//  SixOneTests
//  打开/分享可用性与临时导出。

import AppKit
import Foundation
import Testing
@testable import SixOne

@Suite("条目能否交给外部应用打开")
@MainActor
struct ItemOpenabilityTests {
    @Test("文本条目：有正文即可打开")
    func textItemIsOpenable() throws {
        let harness = try ClipboardHarness()
        let item = try insert(ClipboardItem(kind: .text, text: "内容"), into: harness)

        #expect(harness.manager.canOpenExternally(id: item.id))
    }

    @Test("位图条目：没有源文件（截图），但位图在库里 → 可打开")
    func bitmapItemIsOpenable() throws {
        let harness = try ClipboardHarness()
        let item = try insert(
            ClipboardItem(kind: .image, imageData: Data([0x89, 0x50, 0x4E, 0x47]), contentType: "PNG"),
            into: harness
        )

        #expect(harness.manager.hasInlineImage(id: item.id))
        #expect(harness.manager.canOpenExternally(id: item.id))
    }

    @Test("图片条目：有源文件时按源文件判定，位图不在库里也放行")
    func imageItemWithSourceFileIsOpenable() throws {
        let harness = try ClipboardHarness()
        let file = try TemporaryFiles.makeFile(prefix: "sixone-openable", contents: "hello")
        defer { try? FileManager.default.removeItem(at: file) }
        let item = try insert(
            ClipboardItem(kind: .image, filePath: file.path, contentType: "PNG"),
            into: harness
        )

        #expect(!harness.manager.hasInlineImage(id: item.id))
        #expect(harness.manager.canOpenExternally(id: item.id))
    }

    @Test("文件条目：文件还在 → 可打开；文件被删掉 → 置灰")
    func fileItemFollowsFileExistence() throws {
        let harness = try ClipboardHarness()
        let file = try TemporaryFiles.makeFile(prefix: "sixone-openable", contents: "hello")
        let item = try insert(ClipboardItem(kind: .file, filePath: file.path), into: harness)
        #expect(harness.manager.canOpenExternally(id: item.id))

        try FileManager.default.removeItem(at: file)

        #expect(!harness.manager.canOpenExternally(id: item.id))
    }

    @Test("取不到条目 → 不可打开")
    func unknownItemIsNotOpenable() throws {
        let harness = try ClipboardHarness()

        #expect(!harness.manager.canOpenExternally(id: UUID()))
        #expect(harness.manager.fetchLightItem(id: UUID()) == nil)
    }

    @Test("轻量取数保留身份与路径：判类型、找落点都够用")
    func lightFetchKeepsIdentityAndPaths() throws {
        let harness = try ClipboardHarness()
        let item = try insert(
            ClipboardItem(kind: .file, filePaths: ["/tmp/a.txt", "/tmp/b.txt"]),
            into: harness
        )

        let light = try #require(harness.manager.fetchLightItem(id: item.id))

        #expect(light.id == item.id)
        #expect(light.kind == .file)
        #expect(light.allFilePaths == ["/tmp/a.txt", "/tmp/b.txt"])
    }

    @Test("图片源文件改名后仍可打开（按 bookmark 找当前位置）")
    func imageFollowsBookmark() throws {
        let harness = try ClipboardHarness()
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-openable-image")
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("原名.png")
        try Data([0x00]).write(to: original)
        let bookmark = try #require(
            SecurityScopedFileAccess.payload(forPaths: [original.path]).bookmark
        )
        let item = ClipboardItem(kind: .image, filePath: original.path, contentType: "PNG")
        item.securityScopeBookmark = bookmark
        try insert(item, into: harness)

        let renamed = directory.appendingPathComponent("改名.png")
        try FileManager.default.moveItem(at: original, to: renamed)

        #expect(harness.manager.canOpenExternally(id: item.id))
        let resolved = try #require(harness.manager.fileURL(for: item))
        // /var 解析后带 /private 前缀，比较前统一解开符号链接。
        #expect(
            resolved.resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path
        )
    }

    @Test("链接条目：URL 可解析 → 可打开")
    func linkItemIsOpenable() throws {
        let harness = try ClipboardHarness()
        let item = try insert(ClipboardItem(kind: .link, text: "https://example.com"), into: harness)

        #expect(harness.manager.canOpenExternally(id: item.id))
    }

    @Test("颜色条目：没有外部落点 → 不可打开")
    func colorItemIsNotOpenable() throws {
        let harness = try ClipboardHarness()
        let data = try #require(PasteboardFormat.colorData(of: .red))
        let item = try insert(ClipboardItem(kind: .color, colorData: data), into: harness)

        #expect(!harness.manager.canOpenExternally(id: item.id))
    }

    // MARK: - 打开方式落点

    @Test("纯文本条目：打开方式落成临时 UTF-8 文件")
    func plainTextExportsTemporaryFile() throws {
        let harness = try ClipboardHarness()
        let item = try insert(ClipboardItem(kind: .text, text: "内容"), into: harness)

        let url = try #require(harness.manager.openWithURL(for: item))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(url.pathExtension == "txt")
        #expect(try String(contentsOf: url, encoding: .utf8) == "内容")
    }

    @Test("富文本条目：打开方式落成 RTF 保留格式")
    func richTextExportsRTFFile() throws {
        let harness = try ClipboardHarness()
        let rich = NSAttributedString(string: "富文本")
        let rtf = try rich.data(
            from: NSRange(location: 0, length: rich.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let item = try insert(
            ClipboardItem(kind: .text, text: "富文本", attributedTextData: rtf),
            into: harness
        )

        let url = try #require(harness.manager.openWithURL(for: item))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(url.pathExtension == "rtf")
        #expect(try Data(contentsOf: url) == rtf)
    }

    @Test("内联图片：打开方式落成临时图片文件")
    func inlineImageExportsTemporaryFile() throws {
        let harness = try ClipboardHarness()
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let item = try insert(
            ClipboardItem(kind: .image, imageData: imageData, contentType: "PNG"),
            into: harness
        )

        let url = try #require(harness.manager.openWithURL(for: item))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(url.pathExtension == "png")
        #expect(try Data(contentsOf: url) == imageData)
    }

    @Test("统一打开落点：既无可用源文件也无位图 → nil")
    func openTargetNeedsSomeContent() throws {
        let harness = try ClipboardHarness()
        let item = try insert(
            ClipboardItem(kind: .image, filePath: "/definitely/not/here", contentType: "PNG"),
            into: harness
        )

        #expect(
            harness.manager.openTarget(
                for: item,
                scopedSourceURL: nil,
                preferredFileURL: nil
            ) == nil
        )
    }

    @Test("统一打开落点：源文件可读时优先")
    func openTargetPrefersReadableSource() throws {
        let harness = try ClipboardHarness()
        let file = try TemporaryFiles.makeFile(prefix: "sixone-target", contents: "x")
        defer { try? FileManager.default.removeItem(at: file) }
        let item = try insert(
            ClipboardItem(
                kind: .image,
                imageData: Data([0x89, 0x50, 0x4E, 0x47]),
                filePath: file.path,
                contentType: "PNG"
            ),
            into: harness
        )

        let url = try #require(
            harness.manager.openTarget(
                for: item,
                scopedSourceURL: nil,
                preferredFileURL: nil
            )
        )

        #expect(url.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path)
    }

    @Test("统一打开落点：文件组使用当前文件 URL")
    func openTargetUsesPreferredFileURL() throws {
        let harness = try ClipboardHarness()
        let item = try insert(
            ClipboardItem(kind: .file, filePaths: ["/a", "/b"]),
            into: harness
        )
        let preferred = URL(fileURLWithPath: "/tmp/current.png")

        #expect(
            harness.manager.openTarget(
                for: item,
                scopedSourceURL: nil,
                preferredFileURL: preferred
            ) == preferred
        )
    }

    @Test("文件存在但不可读：视为不可打开、不可分享")
    func unreadableFileIsNotOpenable() throws {
        let harness = try ClipboardHarness()
        let file = try TemporaryFiles.makeFile(prefix: "sixone-unreadable", contents: "x")
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: file.path
            )
            try? FileManager.default.removeItem(at: file)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: file.path
        )
        let item = try insert(ClipboardItem(kind: .file, filePath: file.path), into: harness)

        #expect(!harness.manager.canOpenExternally(id: item.id))
        #expect(
            harness.manager.openTarget(
                for: item,
                scopedSourceURL: nil,
                preferredFileURL: nil
            ) == nil
        )
        #expect(harness.manager.startScopedShareURL(for: item) == nil)
    }

    @Test("打开方式枚举：文本用 0 字节占位文件")
    func textEnumerationUsesEmptyPlaceholder() throws {
        let harness = try ClipboardHarness()
        let item = try insert(ClipboardItem(kind: .text, text: "内容"), into: harness)

        let url = try #require(
            harness.manager.openWithEnumerationURL(for: item, scopedSourceURL: nil)
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(url.pathExtension == "txt")
        #expect(try Data(contentsOf: url).isEmpty)
    }

    @Test("打开方式枚举：源文件可读时直接用源文件")
    func imageEnumerationUsesReadableSource() throws {
        let harness = try ClipboardHarness()
        let source = try TemporaryFiles.makeFile(prefix: "sixone-enum-source", contents: "hello")
        defer { try? FileManager.default.removeItem(at: source) }
        let item = try insert(
            ClipboardItem(
                kind: .image,
                imageData: Data([0x89, 0x50, 0x4E, 0x47]),
                filePath: source.path,
                contentType: "PNG"
            ),
            into: harness
        )

        let url = try #require(
            harness.manager.openWithEnumerationURL(for: item, scopedSourceURL: nil)
        )

        #expect(url.resolvingSymlinksInPath().path == source.resolvingSymlinksInPath().path)
    }

    @Test("打开方式枚举：源文件不可用时按位图格式占位")
    func imageEnumerationUsesBitmapFormat() throws {
        let harness = try ClipboardHarness()
        let tiff = try makeTIFFData()
        let item = try insert(
            ClipboardItem(
                kind: .image,
                imageData: tiff,
                filePath: "/definitely/not/here.tiff",
                contentType: "TIFF"
            ),
            into: harness
        )

        let url = try #require(
            harness.manager.openWithEnumerationURL(for: item, scopedSourceURL: nil)
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(url.pathExtension == "tiff")
        #expect(try Data(contentsOf: url).isEmpty)
    }

    @Test("TIFF 位图按原格式导出，不做格式转换")
    func tiffImageKeepsOriginalFormat() throws {
        let harness = try ClipboardHarness()
        let tiff = try makeTIFFData()
        let item = try insert(
            ClipboardItem(kind: .image, imageData: tiff, contentType: "TIFF"),
            into: harness
        )

        let url = try #require(harness.manager.openWithURL(for: item))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(url.pathExtension == "tiff")
        #expect(try Data(contentsOf: url) == tiff)
    }

    @Test("有内联位图的图片：打开方式导出位图，不碰源文件")
    func imageWithInlineDataExportsBitmap() throws {
        let harness = try ClipboardHarness()
        let source = try TemporaryFiles.makeFile(prefix: "sixone-openwith-source", contents: "hello")
        defer { try? FileManager.default.removeItem(at: source) }
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let item = try insert(
            ClipboardItem(
                kind: .image,
                imageData: imageData,
                filePath: source.path,
                contentType: "PNG"
            ),
            into: harness
        )

        let url = try #require(harness.manager.openWithURL(for: item))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(url.resolvingSymlinksInPath() != source.resolvingSymlinksInPath())
        #expect(url.pathExtension == "png")
        #expect(try Data(contentsOf: url) == imageData)
    }

    @Test("没有位图的图片：打开方式退回源文件")
    func imageWithoutBitmapUsesSource() throws {
        let harness = try ClipboardHarness()
        let file = try TemporaryFiles.makeFile(prefix: "sixone-openwith", contents: "hello")
        defer { try? FileManager.default.removeItem(at: file) }
        let item = try insert(
            ClipboardItem(kind: .image, filePath: file.path, contentType: "PNG"),
            into: harness
        )

        let url = try #require(harness.manager.openWithURL(for: item))

        #expect(url.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path)
    }

    // MARK: - 夹具

    private func makeTIFFData() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        return try #require(bitmap.representation(using: .tiff, properties: [:]))
    }

    @discardableResult
    private func insert(_ item: ClipboardItem, into harness: ClipboardHarness) throws -> ClipboardItem {
        harness.context.insert(item)
        try harness.context.save()
        return item
    }
}
