//
//  ClipboardImageLoaderTests.swift
//  SixOneTests
//  预览图片数据在后台按 id 读取，不占主线程。
//

import Foundation
import Testing
@testable import SixOne

@Suite("预览图片读取")
@MainActor
struct ClipboardImageLoaderTests {
    @Test("后台按 id 读取完整位图")
    func loadsImageData() async throws {
        let harness = try ClipboardHarness()
        let data = Data(repeating: 0x7A, count: 4 * 1024)
        let item = ClipboardItem(kind: .image, imageData: data)
        harness.context.insert(item)
        try harness.context.save()

        let loaded = await harness.manager.loadImageData(id: item.id)
        let missing = await harness.manager.loadImageData(id: UUID())

        #expect(loaded == data)
        #expect(missing == nil)
    }
}
