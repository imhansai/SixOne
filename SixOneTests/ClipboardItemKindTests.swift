//
//  ClipboardItemKindTests.swift
//  SixOneTests

import Testing
@testable import SixOne

/// `hasPlainText` 决定 ⇧⌘C / ⇧⌘V 要不要接管（见 `PanelKeyContextProvider`）。
@Suite("条目类型的纯文本形态")
struct ClipboardItemKindTests {
    @Test("文本 / 链接 / 颜色有正文可当纯文本，图片 / 文件没有")
    func plainTextAvailabilityByKind() {
        #expect(ClipboardItemKind.text.hasPlainText)
        #expect(ClipboardItemKind.link.hasPlainText)
        #expect(ClipboardItemKind.color.hasPlainText)
        #expect(!ClipboardItemKind.image.hasPlainText)
        #expect(!ClipboardItemKind.file.hasPlainText)
    }
}
