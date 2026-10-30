//
//  HistoryBenchmarkTests.swift
//  SixOneTests
//  默认跳过；写入 /tmp/sixone-benchmark 或 .benchmark-history 后跑真实文件库基准。

import AppKit
import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import SixOne

/// 基准开关：内容为条目数的文件。
nonisolated enum HistoryBenchmarkSwitch {
    static var candidates: [URL] {
        [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".benchmark-history"),
            URL(fileURLWithPath: "/tmp/sixone-benchmark"),
        ]
    }

    static var itemCount: Int? {
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let raw = String(data: data, encoding: .utf8),
                  let count = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                  count > 0 else { continue }
            return count
        }
        return nil
    }
}

@Suite("历史规模基准")
@MainActor
struct HistoryBenchmarkTests {
    @Test(
        "浏览窗口 / 搜索 / 启动重建 / 取数 / 窗口内存随条目数怎么变",
        .enabled(if: HistoryBenchmarkSwitch.itemCount != nil)
    )
    func measuresScale() async throws {
        let count = try #require(HistoryBenchmarkSwitch.itemCount)
        let fixture = try BenchmarkFixture()
        defer { fixture.cleanUp() }
        let container = AppModelContainer.make(isStoredInMemoryOnly: false, storeURL: fixture.storeURL)
        let context = container.mainContext
        let repository = SwiftDataHistoryRepository(container: container)
        print("BENCH ==== 条目数 \(count) ====")

        var imageID: UUID?
        try await timed("写入 \(count) 条（2000 条/批，含正文快照与去重快照）") {
            for start in stride(from: 0, to: count, by: 2000) {
                for index in start..<min(start + 2000, count) {
                    let item = Self.makeItem(index: index)
                    context.insert(item)
                    if item.kind == .image { imageID = item.id }
                }
                try context.save()
            }
        }
        let image = try #require(imageID)

        await timed("启动：ClipboardManager 构造 + 保留期裁剪") {
            _ = ClipboardManager(
                container: container,
                settings: SettingsStore(storage: InMemorySettingsStorage()),
                events: ClipboardHistoryEventBus(),
                previewCache: PanelCaches().preview,
                pasteboard: FakePasteboard(),
                frontmostApplication: { nil },
                pollInterval: nil
            )
        }

        let probeKey = try #require(
            try context.fetch(FetchDescriptor<ClipboardItem>()).first?.contentKeySnapshot
        )
        try await timed("去重：按内容 key 查已有条目（等值扫描）") {
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.contentKeySnapshot == probeKey }
            )
            descriptor.fetchLimit = 1
            descriptor.propertiesToFetch = [\.id]
            _ = try context.fetch(descriptor)
        }

        var browseCount = 0
        for limit in [200, 500, 1000] {
            let rows = try await timed("浏览：取最近 \(limit) 条") {
                try await repository.latest(query: "", limit: limit)
            }
            let thumbBytes = rows.reduce(0) { $0 + ($1.thumbnailData?.count ?? 0) }
            let thumbCount = rows.lazy.filter { $0.thumbnailData != nil }.count
            let titleBytes = rows.reduce(0) { $0 + ($1.title?.utf8.count ?? 0) }
            print("BENCH   最近 \(limit) 条取回 \(rows.count) 行：缩略图 \(thumbCount) 张 / \(thumbBytes / 1024) KB，标题 \(titleBytes / 1024) KB")
            if limit == 200 { browseCount = rows.count }
        }
        let docBytes = Self.documentThumbnail?.count ?? 0
        let photoBytes = Self.photoThumbnail?.count ?? 0
        print("BENCH 样本缩略图：文档图标 \(docBytes) B，照片 \(photoBytes) B（HEIC \(Int(ClipboardThumbnailService.listThumbnailPixelSize))px q0.8）")
        print("BENCH 最坏情况（每行都带照片缩略图）：500 条 ≈ \(Self.megabytes(500 * photoBytes)) MB，1000 条 ≈ \(Self.megabytes(1000 * photoBytes)) MB")

        for (label, query) in [("无命中", "绝对不存在的关键词"), ("常见词（约半数命中）", "常见词"), ("罕见词（约 0.1% 命中）", "罕见标记")] {
            let rows = try await timed("搜索：\(label)") {
                try await repository.latest(query: query, limit: 500)
            }
            print("BENCH   命中 \(rows.count) 行")
        }
        let probe = "绝对不存在的关键词"
        try await timed("搜索（对照）：contains（大小写敏感，不可直接用）") {
            _ = try Self.count(context, predicate: #Predicate { $0.searchText?.contains(probe) ?? false })
        }
        try await timed("搜索（对照）：starts(with:) 前缀匹配（B 树索引可用得上）") {
            _ = try Self.count(context, predicate: #Predicate { $0.searchText?.starts(with: probe) ?? false })
        }

        let pasteboardItem = NSPasteboardItem()
        let html = Data(Self.makeHTML(paragraphs: 400).utf8)
        pasteboardItem.setData(html, forType: .html)
        pasteboardItem.setString("网页正文", forType: .string)
        let richTextSnapshot = PasteboardSnapshot.capture(from: [pasteboardItem])
        print("BENCH   富文本样本：\(html.count / 1024) KB HTML")
        await timed("捕获：解析一次富文本复制（HTML → RTF）") {
            _ = PasteboardEntryParser.makeEntry(from: richTextSnapshot)
        }
        await timed("捕获：同一个 HTML → RTF 放到后台线程") {
            let converted = await Task.detached(priority: .userInitiated) { () -> Data? in
                guard let attributed = NSAttributedString(
                    html: html,
                    options: [.characterEncoding: String.Encoding.utf8.rawValue],
                    documentAttributes: nil
                ) else { return nil }
                return try? attributed.data(
                    from: NSRange(location: 0, length: attributed.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
            }.value
            print("BENCH   后台转换产出 \(converted?.count ?? 0) 字节")
        }

        let files = try TemporaryFiles.makeFiles(count: 100, prefix: "sixone-bench-files")
        defer { try? FileManager.default.removeItem(at: files.directory) }
        await timed("捕获：为 100 个文件固化安全作用域 bookmark") {
            _ = SecurityScopedFileAccess.payload(forPaths: files.paths)
        }
        try await timed("捕获：单条写入（insert + save 一次，文本）") {
            context.insert(Self.makeItem(index: count + 1))
            try context.save()
        }

        let benchPasteboard = FakePasteboard()
        let manager = ClipboardManager(
            container: container,
            settings: SettingsStore(storage: InMemorySettingsStorage()),
            events: ClipboardHistoryEventBus(),
            previewCache: PanelCaches().preview,
            pasteboard: benchPasteboard,
            frontmostApplication: { nil },
            pollInterval: nil
        )
        await timed("取数：8KB 位图条目整条读出（fetchFullItem + imageData）") {
            _ = manager.fetchFullItem(id: image)?.imageData?.count
        }
        await timed("取数：8KB 位图条目判「能否外部打开」（fetchLightItem + 存在性探测）") {
            _ = manager.canOpenExternally(id: image)
        }

        let screenshot = Data(repeating: 0x7E, count: 3 * 1024 * 1024)
        let screenshotItem = ClipboardItem(kind: .image, imageData: screenshot, contentType: "PNG")
        screenshotItem.refreshTitleSnapshot()
        screenshotItem.refreshContentKey()
        context.insert(screenshotItem)
        try context.save()
        print("BENCH   截图样本：3 MB 位图")
        await timed("取数：3MB 位图条目整条读出（fetchFullItem + imageData）") {
            _ = manager.fetchFullItem(id: screenshotItem.id)?.imageData?.count
        }
        await timed("取数：3MB 位图条目判「能否外部打开」（fetchLightItem + 存在性探测）") {
            _ = manager.canOpenExternally(id: screenshotItem.id)
        }

        benchPasteboard.simulateCopy([pasteboardItem])
        await timed("捕获：轮询返回（主线程只取快照）") {
            manager.pollPasteboard()
        }
        await timed("捕获：等到入库落定（后台解析 → 主线程写库）") {
            await manager.waitForPendingCapture()
        }

        let bigImageItem = NSPasteboardItem()
        bigImageItem.setData(Data(repeating: 0x11, count: 8 * 1024 * 1024), forType: .png)
        bigImageItem.setData(Data(repeating: 0x22, count: 8 * 1024 * 1024), forType: .tiff)
        await timed("捕获：取一份 8MB PNG + 8MB TIFF 的快照（主线程拷字节）") {
            _ = PasteboardSnapshot.capture(from: [bigImageItem])
        }

        print("BENCH 库目录体积：\(fixture.totalBytes / 1024 / 1024) MB")
        #expect(browseCount == min(200, count))
    }

    // MARK: - 夹具

    private static let photoThumbnail = makeSampleThumbnail(noisy: true)
    private static let documentThumbnail = makeSampleThumbnail(noisy: false)

    private static func makeSampleThumbnail(noisy: Bool) -> Data? {
        let side = Int(ClipboardThumbnailService.listThumbnailPixelSize)
        guard let context = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // 固定种子，保证每次字节数一致，基准可比较。
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat((seed >> 33) % 1000) / 1000
        }
        if noisy {
            for _ in 0..<600 {
                context.setFillColor(CGColor(red: next(), green: next(), blue: next(), alpha: 1))
                context.fill(CGRect(
                    x: next() * CGFloat(side), y: next() * CGFloat(side),
                    width: next() * 48 + 4, height: next() * 48 + 4
                ))
            }
        } else {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.setFillColor(CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1))
            for line in 0..<8 {
                context.fill(CGRect(x: 32, y: 32 + CGFloat(line) * 24, width: 192, height: 8))
            }
        }
        guard let image = context.makeImage() else { return nil }
        return ClipboardThumbnailService.encode(image, as: .heic, quality: 0.8)
            ?? ClipboardThumbnailService.encode(image, as: .png)
    }

    private static func makeItem(index: Int) -> ClipboardItem {
        let item: ClipboardItem
        switch index % 10 {
        case 7, 8:
            item = ClipboardItem(
                kind: .file,
                thumbnailData: Self.documentThumbnail,
                filePaths: ["/tmp/基准/文件\(index).pdf"]
            )
        case 9:
            item = ClipboardItem(
                kind: .image,
                imageData: Data(repeating: UInt8(index % 251), count: 8 * 1024),
                thumbnailData: Self.photoThumbnail,
                contentType: "PNG"
            )
        default:
            var text = "第 \(index) 条历史：一段长度接近真实粘贴内容的正文，用来量搜索谓词的扫描成本。"
            if index.isMultiple(of: 2) { text += " 常见词" }
            if index.isMultiple(of: 1000) { text += " 罕见标记" }
            item = ClipboardItem(kind: .text, text: text)
        }
        // 与生产一致：写入时带上三条快照列。
        item.refreshTitleSnapshot()
        item.refreshContentKey()
        item.refreshFilePathsSearchText()
        return item
    }

    private static func makeHTML(paragraphs: Int) -> String {
        var html = "<html><body>"
        for index in 0..<paragraphs {
            html += "<p><b>第 \(index) 段</b>：<span style=\"color:#333\">这是用来量富文本转换成本的正文。</span></p>"
        }
        html += "</body></html>"
        return html
    }

    @discardableResult
    private func timed<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
        let start = ContinuousClock.now
        let value = try await body()
        print("BENCH \(label): \(Self.milliseconds(ContinuousClock.now - start)) ms")
        return value
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let components = duration.components
        let value = Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
        return String(format: "%.2f", value)
    }

    private static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576)
    }

    private static func count(
        _ context: ModelContext,
        predicate: Predicate<ClipboardItem>
    ) throws -> Int {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: predicate)
        descriptor.fetchLimit = 200
        descriptor.propertiesToFetch = [\.id]
        return try context.fetch(descriptor).count
    }

    @MainActor
    private struct BenchmarkFixture {
        let directory: URL
        let storeURL: URL

        init() throws {
            directory = try TemporaryFiles.makeDirectory(prefix: "sixone-bench")
            storeURL = directory.appendingPathComponent("default.store")
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }

        var totalBytes: Int {
            let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            var total = 0
            while let url = enumerator?.nextObject() as? URL {
                total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
            return total
        }
    }
}
