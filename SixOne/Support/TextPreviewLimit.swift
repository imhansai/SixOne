//
//  TextPreviewLimit.swift
//  SixOne
//
//  文本预览的渲染上限；超出的正文仍完整保存在条目里，只影响显示。
//

import Foundation

nonisolated enum TextPreviewLimit {
    /// `utf8.count` 是 O(1)，可在 body 里反复判断。
    static let maxUTF8Bytes = 4 * 1024 * 1024
    /// 富文本超过这个大小就不再解析，直接显示纯文本。
    static let maxRichTextBytes = 8 * 1024 * 1024
    /// 截断后保留的字符数；只在上限触发时执行。
    static let displayedCharacters = 1_000_000

    static func exceeds(plainText: String?, attributedTextData: Data?) -> Bool {
        (plainText?.utf8.count ?? 0) > maxUTF8Bytes
            || (attributedTextData?.count ?? 0) > maxRichTextBytes
    }

    static func truncated(_ text: String) -> String {
        String(text.prefix(displayedCharacters))
    }
}

extension ClipboardItem {
    /// 超过上限时只渲染开头一段，并停用编辑，避免把截断内容写回条目。
    var exceedsTextPreviewLimit: Bool {
        TextPreviewLimit.exceeds(plainText: text, attributedTextData: attributedTextData)
    }
}
