//
//  TextPreviewLimitTests.swift
//  SixOneTests
//

import Foundation
import Testing
@testable import SixOne

@Suite("文本预览上限")
@MainActor
struct TextPreviewLimitTests {
    @Test("正文或富文本超过上限会被识别")
    func detectsOversizedContent() {
        let bigText = String(repeating: "a", count: TextPreviewLimit.maxUTF8Bytes + 1)
        #expect(TextPreviewLimit.exceeds(plainText: bigText, attributedTextData: nil))
        #expect(!TextPreviewLimit.exceeds(plainText: "small", attributedTextData: nil))
        #expect(TextPreviewLimit.exceeds(
            plainText: "small",
            attributedTextData: Data(repeating: 0, count: TextPreviewLimit.maxRichTextBytes + 1)
        ))
    }

    @Test("截断只保留开头的显示长度")
    func truncatesToDisplayedLength() {
        let text = String(repeating: "六", count: TextPreviewLimit.displayedCharacters + 10)
        #expect(TextPreviewLimit.truncated(text).count == TextPreviewLimit.displayedCharacters)
        #expect(TextPreviewLimit.truncated("短文本") == "短文本")
    }

    @Test("超上限的条目不能进入编辑态")
    func oversizedItemCannotStartEditing() {
        let state = PreviewState()
        state.item = ClipboardItem(kind: .text, text: "small")
        state.startEditing()
        #expect(state.isEditing)

        state.cancelEditing()
        state.item = ClipboardItem(
            kind: .text,
            text: String(repeating: "a", count: TextPreviewLimit.maxUTF8Bytes + 1)
        )
        state.startEditing()
        #expect(!state.isEditing)
    }
}
