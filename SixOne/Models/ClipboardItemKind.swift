//
//  ClipboardItemKind.swift
//  SixOne
//
//  条目类型。独立于模型文件，避免与持久化模型耦合。
//

enum ClipboardItemKind: String, Sendable {
    case text
    case image
    case file
    case link
    case color

    /// 是否有纯文本形态：文本/链接的正文、颜色的十六进制；图片与文件没有。
    var hasPlainText: Bool {
        switch self {
        case .text, .link, .color: true
        case .image, .file: false
        }
    }
}
