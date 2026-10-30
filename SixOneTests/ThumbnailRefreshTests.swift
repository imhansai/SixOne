//
//  ThumbnailRefreshTests.swift
//  SixOneTests
//  旧尺寸缩略图按当前版本惰性重算；已是当前版本的不重复生成。
//

import AppKit
import ImageIO
import Testing
@testable import SixOne

@Suite("缩略图重算")
@MainActor
struct ThumbnailRefreshTests {
    @Test("旧版本缩略图重算后更新尺寸版本")
    func refreshesLegacyThumbnail() async throws {
        let harness = try ClipboardHarness()
        let item = try makeColorItem(version: ClipboardItem.legacyThumbnailVersion, in: harness)

        harness.manager.refreshThumbnail(id: item.id)
        await harness.manager.waitForPendingThumbnails()

        let refreshed = try #require(harness.manager.fetchFullItem(id: item.id))
        #expect(refreshed.thumbnailVersion == ClipboardItem.currentThumbnailVersion)
        #expect(refreshed.thumbnailData != nil)
    }

    @Test("缩略图按请求的边长生成")
    func honorsRequestedPixelSize() async throws {
        let color = try #require(PasteboardFormat.colorData(
            of: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        ))
        let data = try #require(await ClipboardThumbnailService.makeThumbnail(
            from: .color(color),
            pixelSize: 128
        ))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 128)
        #expect(image.height == 128)
    }

    @Test("当前版本的缩略图不会重复重算")
    func currentVersionIsIgnored() async throws {
        let harness = try ClipboardHarness()
        let item = try makeColorItem(version: ClipboardItem.currentThumbnailVersion, in: harness)
        let before = item.thumbnailData

        harness.manager.refreshThumbnail(id: item.id)
        await harness.manager.waitForPendingThumbnails()

        let refreshed = try #require(harness.manager.fetchFullItem(id: item.id))
        #expect(refreshed.thumbnailVersion == ClipboardItem.currentThumbnailVersion)
        #expect(refreshed.thumbnailData == before)
    }

    private func makeColorItem(
        version: Int,
        in harness: ClipboardHarness
    ) throws -> ClipboardItem {
        let color = try #require(PasteboardFormat.colorData(
            of: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        ))
        let item = ClipboardItem(
            kind: .color,
            thumbnailData: Data([0x00]),
            colorData: color
        )
        item.thumbnailVersion = version
        item.refreshTitleSnapshot()
        item.refreshContentKey()
        harness.context.insert(item)
        try harness.context.save()
        return item
    }
}
