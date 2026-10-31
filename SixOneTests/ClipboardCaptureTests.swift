//
//  ClipboardCaptureTests.swift
//  SixOneTests

import AppKit
import Foundation
import ImageIO
import Testing
@testable import SixOne

/// 解析在后台线程，轮询后须 `pollAndWait()` 再断言；假剪贴板不碰真实剪贴板。
@Suite("剪贴板捕获")
@MainActor
struct ClipboardCaptureTests {
    @Test("外部复制新内容：入库并广播 inserted")
    func capturesNewContent() async throws {
        let harness = try ClipboardHarness()

        harness.pasteboard.simulateCopy(text: "hello")
        await harness.pollAndWait()

        let items = harness.itemsNewestFirst()
        #expect(items.count == 1)
        #expect(items.first?.text == "hello")
        #expect(harness.recorder.events == [.inserted(id: items[0].id)])
    }

    @Test("复制空或纯空白文本：不产生条目")
    func ignoresEmptyText() async throws {
        let harness = try ClipboardHarness()

        harness.pasteboard.simulateCopy(text: "")
        await harness.pollAndWait()
        harness.pasteboard.simulateCopy(text: "   \n\t")
        await harness.pollAndWait()

        #expect(harness.itemsNewestFirst().isEmpty)
        #expect(harness.recorder.events.isEmpty)
    }

    @Test("changeCount 没变时什么都不做")
    func ignoresUnchangedPasteboard() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "hello")
        await harness.pollAndWait()

        await harness.pollAndWait()

        #expect(harness.itemsNewestFirst().count == 1)
        #expect(harness.recorder.events.count == 1)
    }

    @Test("复制后还没轮询：能探测到未认领的变化，轮询后清除")
    func detectsUnpolledPasteboardChange() async throws {
        let harness = try ClipboardHarness()
        #expect(!harness.manager.hasUnpolledPasteboardChange)

        harness.pasteboard.simulateCopy(text: "hello")
        #expect(harness.manager.hasUnpolledPasteboardChange)

        await harness.pollAndWait()
        #expect(!harness.manager.hasUnpolledPasteboardChange)
    }

    @Test("重复复制同一内容：不新增条目，原位置顶并广播 touched")
    func deduplicatesAndTouches() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "same")
        await harness.pollAndWait()
        let first = try #require(harness.itemsNewestFirst().first)
        let recencyBefore = first.recencyID

        harness.pasteboard.simulateCopy(text: "same")
        await harness.pollAndWait()

        #expect(harness.itemsNewestFirst().count == 1)
        let after = try #require(harness.itemsNewestFirst().first)
        #expect(after.id == first.id)
        #expect(after.recencyID > recencyBefore)
        #expect(harness.recorder.events == [
            .inserted(id: first.id),
            .touched(id: first.id, isExternal: true),
        ])
    }

    @Test("连着复制两次：解析在后台也不会乱序，两次都入库且按复制顺序排列")
    func keepsCaptureOrder() async throws {
        let harness = try ClipboardHarness()

        // 两次轮询不等结果，第二次快照在首次解析未回时即取。
        harness.pasteboard.simulateCopy(text: "第一次")
        harness.manager.pollPasteboard()
        harness.pasteboard.simulateCopy(text: "第二次")
        harness.manager.pollPasteboard()
        await harness.manager.waitForPendingCapture()

        #expect(harness.itemsNewestFirst().map(\.text) == ["第二次", "第一次"])
        #expect(harness.recorder.events.count == 2)
    }

    @Test("重启后仍能去重：去重不依赖常驻内存的索引")
    func dedupSurvivesRestart() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "same")
        await harness.pollAndWait()
        let first = try #require(harness.itemsNewestFirst().first)
        let recencyBefore = first.recencyID

        let restarted = ClipboardManager(
            container: harness.container,
            settings: harness.settings,
            events: ClipboardHistoryEventBus(),
            previewCache: PanelCaches().preview,
            pasteboard: harness.pasteboard,
            frontmostApplication: { harness.frontmost.source },
            pollInterval: nil
        )
        harness.pasteboard.simulateCopy(text: "same")
        restarted.pollPasteboard()
        await restarted.waitForPendingCapture()

        let items = harness.itemsNewestFirst()
        #expect(items.count == 1)
        #expect(items.first?.id == first.id)
        #expect(items.first?.recencyID != recencyBefore)
    }

    @Test("快照为空的条目不参与去重（行为约定）")
    func rowWithoutSnapshotDoesNotDedup() async throws {
        let harness = try ClipboardHarness { context in
            let withoutSnapshot = ClipboardItem(kind: .text, text: "old")
            withoutSnapshot.contentKeySnapshot = nil
            context.insert(withoutSnapshot)
            try context.save()
        }

        harness.pasteboard.simulateCopy(text: "old")
        await harness.pollAndWait()

        #expect(harness.itemsNewestFirst().count == 2)
    }

    @Test("多文件复制记成一条条目，路径顺序即选择顺序")
    func capturesFileGroup() async throws {
        let harness = try ClipboardHarness()

        harness.pasteboard.simulateCopy(fileURLs: [
            URL(fileURLWithPath: "/tmp/a.txt"),
            URL(fileURLWithPath: "/tmp/b.txt"),
        ])
        await harness.pollAndWait()

        let item = try #require(harness.itemsNewestFirst().first)
        #expect(item.kind == .file)
        #expect(item.allFilePaths == ["/tmp/a.txt", "/tmp/b.txt"])
    }

    @Test("从磁盘复制的图片也固化源文件 bookmark")
    func imageFromDiskGetsBookmark() throws {
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-capture-image")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("六一.png")
        try Self.pngBytes.write(to: file)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(file.absoluteString, forType: .fileURL)
        pasteboardItem.setData(Self.pngBytes, forType: .png)
        let prepared = try #require(
            PasteboardEntryParser.prepare(from: PasteboardSnapshot.capture(from: [pasteboardItem]))
        )

        #expect(prepared.entry.kind == .image)
        #expect(prepared.entry.filePath == file.path)
        #expect(prepared.fileAccess.bookmark != nil, "图片的源文件没有固化 bookmark")
    }

    @Test("图片的缩略图取剪贴板位图，不依赖读不到的源文件（微信复制的形态）")
    func imageThumbnailUsesBitmapInsteadOfSourceFile() throws {
        let entry = PasteboardEntryParser.Entry(
            kind: .image,
            imageData: Self.pngBytes,
            filePaths: ["/Users/example/Library/Containers/com.tencent.xinWeChat/Data/temp/copied.jpg"],
            contentType: "TIFF"
        )

        let source = try #require(ClipboardManager.thumbnailSource(for: entry, bookmark: nil))
        guard case let .bitmap(data) = source else {
            Issue.record("图片条目的缩略图应取剪贴板位图，不能走读不到的源文件")
            return
        }
        #expect(data == Self.pngBytes)
    }

    @Test("普通文件条目的缩略图仍按源文件路径取图")
    func fileThumbnailUsesSourcePath() throws {
        let file = try TemporaryFiles.makeFile(prefix: "sixone-thumbnail-source", contents: "x")
        defer { try? FileManager.default.removeItem(at: file) }
        let entry = PasteboardEntryParser.Entry(kind: .file, filePaths: [file.path])

        let source = try #require(ClipboardManager.thumbnailSource(for: entry, bookmark: nil))
        guard case let .file(path, bookmark) = source else {
            Issue.record("文件条目的缩略图应走源文件路径")
            return
        }
        #expect(path == file.path)
        #expect(bookmark == nil)
    }

    @Test("读不到的普通文件不排 Quick Look 缩略图（微信复制的视频就是这种形态）")
    func unreadableFileSkipsQuickLookThumbnail() throws {
        let entry = PasteboardEntryParser.Entry(
            kind: .file,
            filePaths: ["/Users/example/Library/Containers/com.tencent.xinWeChat/Data/temp/copied.mp4"]
        )

        #expect(ClipboardManager.thumbnailSource(for: entry, bookmark: nil) == nil)
    }

    @Test("源文件读不到时，缩略图真的画的是位图内容")
    func unreadableSourceStillYieldsBitmapThumbnail() async throws {
        let harness = try ClipboardHarness()
        // 微信形态：源文件读不到，另给红位图；缩略图应画红色内容而非白色文件图标。
        let item = NSPasteboardItem()
        item.setString("file:///Users/example/Library/Containers/com.tencent.xinWeChat/Data/temp/copied.jpg", forType: .fileURL)
        item.setData(Self.solidRedPNG, forType: .png)
        harness.pasteboard.simulateCopy([item])
        await harness.pollAndWait()
        await harness.drainThumbnails()

        let captured = try #require(harness.itemsNewestFirst().first)
        #expect(captured.kind == .image)
        let thumbnail = try #require(captured.thumbnailData)
        let color = try #require(Self.averageColor(ofImageData: thumbnail))
        #expect(color.red > color.green + 0.15 && color.red > color.blue + 0.15,
                "缩略图平均色 \(color) 不是红色 —— 取到的不是位图内容")
    }

    @Test("来源在隐私忽略列表里时不留痕")
    func skipsIgnoredSource() async throws {
        let harness = try ClipboardHarness(ignoredApps: [
            IgnoredApplication(bundleIdentifier: "com.example.blocked", displayName: "被忽略的应用", path: "/tmp/Blocked.app"),
        ])
        harness.frontmost.source = SourceApplication(bundleIdentifier: "com.example.blocked", name: "被忽略的应用")

        harness.pasteboard.simulateCopy(text: "secret")
        await harness.pollAndWait()

        #expect(harness.itemsNewestFirst().isEmpty)
        #expect(harness.recorder.events.isEmpty)
    }

    @Test("内容被标记为「不要记录」时不留痕（密码管理器的路径）")
    func skipsConcealedContent() async throws {
        let harness = try ClipboardHarness()

        harness.pasteboard.simulateConcealedCopy(text: "correct horse battery staple")
        await harness.pollAndWait()

        #expect(harness.itemsNewestFirst().isEmpty)
        #expect(harness.recorder.events.isEmpty)
    }

    @Test("「不要记录」独立于来源判定：前台应用不在忽略列表里也照样跳过")
    func concealedWinsOverSourceCheck() async throws {
        let harness = try ClipboardHarness()
        harness.frontmost.source = SourceApplication(bundleIdentifier: "com.example.browser", name: "浏览器")

        harness.pasteboard.simulateConcealedCopy(text: "otpauth://totp/Example:me?secret=ABCD")
        await harness.pollAndWait()

        #expect(harness.itemsNewestFirst().isEmpty)
    }

    @Test("SixOne 自己的写入不改来源角标")
    func keepsSourceForOwnWrites() async throws {
        let harness = try ClipboardHarness()
        harness.frontmost.source = SourceApplication(bundleIdentifier: "com.example.editor", name: "编辑器")
        harness.pasteboard.simulateCopy(text: "from editor")
        await harness.pollAndWait()

        harness.frontmost.source = SourceApplication(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            name: "SixOne"
        )
        harness.pasteboard.simulateCopy(text: "from editor")
        await harness.pollAndWait()

        let item = try #require(harness.itemsNewestFirst().first)
        #expect(item.sourceAppBundleIdentifier == "com.example.editor")
        #expect(harness.recorder.events.last == .touched(id: item.id, isExternal: false))
    }

    @Test("整条拷贝：写回剪贴板、置顶，且不会被轮询当成新的外部复制")
    func copyWritesAndDoesNotRecapture() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "first")
        await harness.pollAndWait()
        harness.pasteboard.simulateCopy(text: "second")
        await harness.pollAndWait()
        let older = try #require(harness.itemsNewestFirst().first { $0.text == "first" })

        harness.manager.copy(id: older.id)

        #expect(harness.pasteboard.lastWrite == .text("first", rtf: nil))
        #expect(harness.itemsNewestFirst().first?.id == older.id)

        // 写回后立刻轮询，误当外部复制会多一条事件。
        let eventsAfterCopy = harness.recorder.events
        await harness.pollAndWait()
        #expect(harness.recorder.events == eventsAfterCopy)
    }

    @Test("删除条目会一并释放去重索引")
    func deleteReleasesDedupIndex() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "x")
        await harness.pollAndWait()
        let deleted = try #require(harness.itemsNewestFirst().first)

        harness.manager.delete(id: deleted.id)
        harness.pasteboard.simulateCopy(text: "x")
        await harness.pollAndWait()

        let items = harness.itemsNewestFirst()
        #expect(items.count == 1)
        #expect(items[0].id != deleted.id)
        #expect(harness.recorder.events.last == .inserted(id: items[0].id))
    }

    @Test("清空历史：条目清空并广播 cleared")
    func clearAllRemovesEverything() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "hello")
        await harness.pollAndWait()

        harness.manager.clearAll()

        #expect(harness.itemsNewestFirst().isEmpty)
        #expect(harness.recorder.events.last == .cleared)
    }

    @Test("链接复制（带 public.url 类型）：归为 link，正文是 URL")
    func capturesLinkFromURLType() async throws {
        let harness = try ClipboardHarness()
        let item = NSPasteboardItem()
        item.setString("https://example.com/a", forType: .URL)
        item.setString("https://example.com/a", forType: .string)
        harness.pasteboard.simulateCopy([item])
        await harness.pollAndWait()

        let captured = try #require(harness.itemsNewestFirst().first)
        #expect(captured.kind == .link)
        #expect(captured.text == "https://example.com/a")
    }

    @Test("纯文本恰好是一个 http 链接：也归为 link")
    func capturesBareURLText() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "https://example.com/page")
        await harness.pollAndWait()

        #expect(harness.itemsNewestFirst().first?.kind == .link)
    }

    @Test("一段话里夹着链接仍是文本")
    func keepsTextWithEmbeddedURL() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "看这个 https://example.com 链接")
        await harness.pollAndWait()

        #expect(harness.itemsNewestFirst().first?.kind == .text)
    }

    @Test("同一项既有位图又有 public.url：按链接收；位图单独来仍是图片")
    func linkWinsOverBitmapInSameItem() async throws {
        let harness = try ClipboardHarness()
        let bitmapOnly = NSPasteboardItem()
        bitmapOnly.setData(Self.pngBytes, forType: .png)
        harness.pasteboard.simulateCopy([bitmapOnly])
        await harness.pollAndWait()
        await harness.drainThumbnails()
        #expect(harness.itemsNewestFirst().first?.kind == .image)

        // 同时带 .URL 与位图时按链接收：Safari/Chrome 拷贝图像不写 .URL，不会误伤。
        let both = NSPasteboardItem()
        both.setString("https://example.com/pic.png", forType: .URL)
        both.setString("https://example.com/pic.png", forType: .string)
        both.setData(Self.pngBytes, forType: .png)
        harness.pasteboard.simulateCopy([both])
        await harness.pollAndWait()
        await harness.drainThumbnails()

        let items = harness.itemsNewestFirst()
        #expect(items.count == 2)
        #expect(items.first?.kind == .link)
        #expect(items.first?.text == "https://example.com/pic.png")
        #expect(items.last?.kind == .image)
    }

    @Test("颜色复制（系统属性列表路径）：归为 color，标题是十六进制")
    func capturesColor() async throws {
        let harness = try ClipboardHarness()
        // 复刻 NSColorPanel：颜色走属性列表写入，而非 setData。
        let color = NSColor(
            srgbRed: CGFloat(0xCF) / 255,
            green: CGFloat(0x66) / 255,
            blue: CGFloat(0x8F) / 255,
            alpha: 1
        )
        let item = NSPasteboardItem()
        let plist = try #require(color.pasteboardPropertyList(forType: .color))
        item.setPropertyList(plist, forType: .color)
        harness.pasteboard.simulateCopy([item])
        await harness.pollAndWait()
        await harness.drainThumbnails()

        let captured = try #require(harness.itemsNewestFirst().first)
        #expect(captured.kind == .color)
        #expect(captured.colorHexString == "#CF668F")
        #expect(captured.colorData == plist as? Data)
    }

    @Test("直接 setData 的裸归档也归一成同一个归档本体")
    func normalizesBareColorArchive() async throws {
        let harness = try ClipboardHarness()
        let color = NSColor(srgbRed: 0.5, green: 0.25, blue: 0, alpha: 1)
        let archive = try #require(PasteboardFormat.colorData(of: color))
        let item = NSPasteboardItem()
        item.setData(archive, forType: .color)
        harness.pasteboard.simulateCopy([item])
        await harness.pollAndWait()
        await harness.drainThumbnails()

        let captured = try #require(harness.itemsNewestFirst().first)
        #expect(captured.kind == .color)
        #expect(captured.colorData == archive)
    }

    @Test("hex 文本（#cf668f）：识别为 color，标题是十六进制，原文保留供写回")
    func capturesHexColorText() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "#cf668f")
        await harness.pollAndWait()
        await harness.drainThumbnails()

        let captured = try #require(harness.itemsNewestFirst().first)
        #expect(captured.kind == .color)
        #expect(captured.text == "#cf668f")
        #expect(captured.colorHexString == "#CF668F")
        let sameColor = NSColor(srgbRed: CGFloat(0xCF) / 255, green: CGFloat(0x66) / 255, blue: CGFloat(0x8F) / 255, alpha: 1)
        #expect(captured.colorData == PasteboardFormat.colorData(of: sameColor))
    }

    @Test("同一个颜色：色板复制与 hex 文本复制命中去重，不新增条目")
    func deduplicatesColorAcrossSources() async throws {
        let harness = try ClipboardHarness()
        let color = NSColor(srgbRed: CGFloat(0xCF) / 255, green: CGFloat(0x66) / 255, blue: CGFloat(0x8F) / 255, alpha: 1)
        let item = NSPasteboardItem()
        item.setPropertyList(try #require(color.pasteboardPropertyList(forType: .color)), forType: .color)
        harness.pasteboard.simulateCopy([item])
        await harness.pollAndWait()
        await harness.drainThumbnails()
        let first = try #require(harness.itemsNewestFirst().first)

        harness.pasteboard.simulateCopy(text: "#cf668f")
        await harness.pollAndWait()
        await harness.drainThumbnails()

        let items = harness.itemsNewestFirst()
        #expect(items.count == 1)
        #expect(items.first?.id == first.id)
        #expect(items.first?.text == "#cf668f")
    }

    @Test("不带 # 的 hex 单词仍是文本，不误判成颜色")
    func keepsBareHexWordAsText() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "facade")
        await harness.pollAndWait()

        #expect(harness.itemsNewestFirst().first?.kind == .text)
    }

    @Test("裸色号（D5A18E）：也识别为 color，原文保留供写回")
    func capturesBareHexColor() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "D5A18E")
        await harness.pollAndWait()
        await harness.drainThumbnails()

        let captured = try #require(harness.itemsNewestFirst().first)
        #expect(captured.kind == .color)
        #expect(captured.text == "D5A18E")
        #expect(captured.colorHexString == "#D5A18E")
        #expect(captured.displayTitle == "#D5A18E")
    }

    @Test("裸色号与带 # 的同一颜色命中去重")
    func deduplicatesBareHexWithHashedHex() async throws {
        let harness = try ClipboardHarness()
        harness.pasteboard.simulateCopy(text: "#d5a18e")
        await harness.pollAndWait()
        await harness.drainThumbnails()
        let first = try #require(harness.itemsNewestFirst().first)

        harness.pasteboard.simulateCopy(text: "D5A18E")
        await harness.pollAndWait()
        await harness.drainThumbnails()

        let items = harness.itemsNewestFirst()
        #expect(items.count == 1)
        #expect(items.first?.id == first.id)
        #expect(items.first?.text == "D5A18E")
    }

    @Test("纯字母的六位十六进制仍是文本（与单词在形状上无法区分）")
    func keepsAllLetterHexAsText() async throws {
        let harness = try ClipboardHarness()
        for text in ["beefed", "FFFFFF", "AABBCC"] {
            harness.pasteboard.simulateCopy(text: text)
            await harness.pollAndWait()
        }

        #expect(harness.itemsNewestFirst().allSatisfy { $0.kind == .text })
    }

    @Test("PNG 与 TIFF 同时存在时只读 PNG，避免主线程重复拷位图")
    func snapshotPrefersPNGOverTIFF() throws {
        let image = try #require(NSImage(data: Self.pngBytes))
        let tiff = try #require(image.tiffRepresentation)
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(Self.pngBytes, forType: .png)
        pasteboardItem.setData(tiff, forType: .tiff)

        let snapshot = PasteboardSnapshot.capture(from: [pasteboardItem])

        #expect(snapshot.items.first?.data(.png) != nil)
        #expect(snapshot.items.first?.data(.tiff) == nil)
    }

    // MARK: - 夹具

    /// 真实可解码的 1×1 PNG：`isBitmap` 校验容器头，随手造的字节过不了。
    private static let pngBytes = Data(
        base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
        """
    )!

    private static let solidRedPNG: Data = {
        let side = 128
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let pixels = rep.bitmapData!
        for index in stride(from: 0, to: side * side * 4, by: 4) {
            pixels[index] = 230
            pixels[index + 1] = 30
            pixels[index + 2] = 30
            pixels[index + 3] = 255
        }
        return rep.representation(using: .png, properties: [:])!
    }()

    private static func averageColor(ofImageData data: Data) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }
}
