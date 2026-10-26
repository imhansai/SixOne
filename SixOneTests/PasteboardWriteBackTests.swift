//
//  PasteboardWriteBackTests.swift
//  SixOneTests
//  写回剪贴板：整条拷贝与编辑保存须原样回写，用内存剪贴板避免污染真实剪贴板。

import AppKit
import Foundation
import Testing
@testable import SixOne

@Suite("写回剪贴板")
@MainActor
struct PasteboardWriteBackTests {
    @Test("文本条目：带富文本原样写回")
    func writesTextWithRichText() throws {
        let harness = try ClipboardHarness()
        let rtf = Data("{\\rtf1\\ansi 富文本}".utf8)
        let item = try insert(ClipboardItem(kind: .text, text: "富文本", attributedTextData: rtf), into: harness)

        harness.manager.copy(item)

        #expect(harness.pasteboard.lastWrite == .text("富文本", rtf: rtf))
    }

    @Test("纯文本拷贝：只写文字，不带富文本")
    func writesPlainTextOnly() throws {
        let harness = try ClipboardHarness()
        let rtf = Data("{\\rtf1\\ansi 富文本}".utf8)
        let item = try insert(ClipboardItem(kind: .text, text: "富文本", attributedTextData: rtf), into: harness)

        harness.manager.copyAsPlainText(item)

        #expect(harness.pasteboard.lastWrite == .text("富文本", rtf: nil))
    }

    @Test("图片条目：按 contentType 选粘贴板类型")
    func writesImageWithPasteboardType() throws {
        let harness = try ClipboardHarness()
        let bitmap = Data([0x49, 0x49, 0x2A, 0x00])
        let tiff = try insert(
            ClipboardItem(kind: .image, imageData: bitmap, contentType: "TIFF"),
            into: harness
        )
        let png = try insert(
            ClipboardItem(kind: .image, imageData: bitmap, contentType: "PNG"),
            into: harness
        )

        harness.manager.copy(tiff)
        #expect(harness.pasteboard.lastWrite == .image(bitmap, type: .tiff))

        harness.manager.copy(png)
        #expect(harness.pasteboard.lastWrite == .image(bitmap, type: .png))
    }

    @Test("文件组：解析得到几个就写几个 URL，顺序不变")
    func writesFileGroupInOrder() throws {
        let harness = try ClipboardHarness()
        let files = try TemporaryFiles.makeFiles(count: 3, prefix: "sixone-writeback")
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let item = try insert(ClipboardItem(kind: .file, filePaths: files.paths), into: harness)

        harness.manager.copy(item)

        #expect(harness.pasteboard.lastWrite == .fileURLs(files.paths.map(URL.init(fileURLWithPath:))))
    }

    @Test("文件失联：仍按原始路径回写，而不是清空剪贴板")
    func keepsOriginalPathsWhenFilesAreGone() throws {
        let harness = try ClipboardHarness()
        let paths = ["/definitely/not/here-\(UUID().uuidString).txt"]
        let item = try insert(ClipboardItem(kind: .file, filePaths: paths), into: harness)

        harness.manager.copy(item)

        // 清空会让用户粘出空内容，保留原路径至少保留了意图。
        #expect(harness.pasteboard.lastWrite == .fileURLs(paths.map(URL.init(fileURLWithPath:))))
    }

    @Test("文件条目连路径都没有：清空剪贴板，不写半截内容")
    func clearsWhenThereIsNothingToWrite() throws {
        let harness = try ClipboardHarness()
        let item = try insert(ClipboardItem(kind: .file), into: harness)

        harness.manager.copy(item)

        #expect(harness.pasteboard.lastWrite == .clear)
    }

    @Test("编辑保存：写回剪贴板、触达置顶，并刷新去重快照")
    func editingWritesBackAndRefreshesDedup() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "改之前")
        await harness.pollAndWait()
        let item = try #require(harness.itemsNewestFirst().first)
        let recencyBefore = item.recencyID

        item.text = "改之后"
        item.refreshTitleSnapshot()
        harness.manager.update(item)

        #expect(harness.pasteboard.lastWrite == .text("改之后", rtf: nil))
        #expect(item.recencyID != recencyBefore)

        harness.pasteboard.simulateCopy(text: "改之后")
        await harness.pollAndWait()

        let items = harness.itemsNewestFirst()
        #expect(items.count == 1)
        #expect(items.first?.id == item.id)
    }

    @Test("编辑保存把正文清空：删除该条，不留内容空白的条目")
    func editingToEmptyDeletesItem() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "要删掉的")
        await harness.pollAndWait()
        let id = try #require(harness.itemsNewestFirst().first).id

        harness.manager.updateEditedText(id: id, text: "   \n", richText: nil)

        #expect(harness.itemsNewestFirst().isEmpty)
        #expect(harness.recorder.events.last == .deleted(id: id))
    }

    @Test("链接条目：写回 URL 类型与纯文本")
    func writesLink() throws {
        let harness = try ClipboardHarness()
        let item = try insert(ClipboardItem(kind: .link, text: "https://example.com/x"), into: harness)

        harness.manager.copy(item)

        #expect(harness.pasteboard.lastWrite == .url("https://example.com/x"))
    }

    @Test("链接条目：正文编辑成不可解析的文本时按纯文本写回，不往 .URL 里塞无效内容")
    func writesEditedLinkAsPlainText() throws {
        let harness = try ClipboardHarness()
        let item = try insert(ClipboardItem(kind: .link, text: "https://example.com/x"), into: harness)

        item.text = "改坏的链接"
        harness.manager.update(item)

        #expect(harness.pasteboard.lastWrite == .text("改坏的链接", rtf: nil))
    }

    @Test("链接条目编辑保存：写回新链接，去重键跟着新正文走")
    func updatesEditedLink() throws {
        let harness = try ClipboardHarness()
        let item = try insert(ClipboardItem(kind: .link, text: "https://example.com/a"), into: harness)

        item.text = "https://example.com/b"
        harness.manager.update(item)

        #expect(harness.pasteboard.lastWrite == .url("https://example.com/b"))
        #expect(
            item.contentKeySnapshot == ClipboardItem.contentKey(
                kind: .link,
                text: "https://example.com/b",
                imageData: nil,
                filePaths: []
            )
        )
    }

    @Test("颜色条目：颜色与文本一起写回（色板来源现推十六进制）")
    func writesColor() throws {
        let harness = try ClipboardHarness()
        let data = try #require(PasteboardFormat.colorData(of: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)))
        let item = try insert(ClipboardItem(kind: .color, colorData: data), into: harness)

        harness.manager.copy(item)

        #expect(harness.pasteboard.lastWrite == .color(text: "#0000FF", archive: data))
    }

    @Test("hex 文本颜色：颜色与原文一起写回，文本保留用户的写法")
    func writesHexColorWithItsText() throws {
        let harness = try ClipboardHarness()
        let data = try #require(PasteboardFormat.colorData(of: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)))
        let item = try insert(ClipboardItem(kind: .color, text: "#cf668f", colorData: data), into: harness)

        harness.manager.copy(item)

        #expect(harness.pasteboard.lastWrite == .color(text: "#cf668f", archive: data))
    }

    @Test("颜色条目的纯文本拷贝：hex 文本来源给原文，色板来源给十六进制")
    func copiesColorAsPlainText() throws {
        let harness = try ClipboardHarness()
        let data = try #require(PasteboardFormat.colorData(of: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)))
        let fromText = try insert(ClipboardItem(kind: .color, text: "#cf668f", colorData: data), into: harness)
        let fromPanel = try insert(ClipboardItem(kind: .color, colorData: data), into: harness)

        harness.manager.copyAsPlainText(fromText)
        #expect(harness.pasteboard.lastWrite == .text("#cf668f", rtf: nil))

        harness.manager.copyAsPlainText(fromPanel)
        #expect(harness.pasteboard.lastWrite == .text("#0000FF", rtf: nil))
    }

    @Test("复制任意一段纯文本（链接预览的协议/主机/端口）：只写剪贴板，不进历史也不置顶")
    func copiesArbitraryPlainText() async throws {
        let harness = try ClipboardHarness()
        let item = try insert(
            ClipboardItem(kind: .link, text: "http://8.135.111.51:3000/explore"),
            into: harness
        )
        let recencyBefore = item.recencyID

        harness.manager.copyPlainText("http://8.135.111.51:3000")

        #expect(harness.pasteboard.lastWrite == .text("http://8.135.111.51:3000", rtf: nil))
        // 自己写回不应被轮询当成外部复制，也不置顶。
        await harness.pollAndWait()
        let items = harness.itemsNewestFirst()
        #expect(items.count == 1)
        #expect(items.first?.recencyID == recencyBefore)
    }

    // MARK: - 夹具

    @discardableResult
    private func insert(_ item: ClipboardItem, into harness: ClipboardHarness) throws -> ClipboardItem {
        harness.context.insert(item)
        try harness.context.save()
        return item
    }
}
