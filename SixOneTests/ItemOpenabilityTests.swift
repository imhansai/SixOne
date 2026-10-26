//
//  ItemOpenabilityTests.swift
//  SixOneTests
//  打开/分享可用性：同步判定，只读轻量列。

import Foundation
import Testing
@testable import SixOne

@Suite("条目能否交给外部应用打开")
@MainActor
struct ItemOpenabilityTests {
    @Test("文本条目：没有可交给外部应用的落点")
    func textItemIsNotOpenable() throws {
        let harness = try ClipboardHarness()
        let item = try insert(ClipboardItem(kind: .text, text: "内容"), into: harness)

        #expect(!harness.manager.canOpenExternally(id: item.id))
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

    // MARK: - 夹具

    @discardableResult
    private func insert(_ item: ClipboardItem, into harness: ClipboardHarness) throws -> ClipboardItem {
        harness.context.insert(item)
        try harness.context.save()
        return item
    }
}
