//
//  ItemCommand.swift
//  SixOne
//
//  条目动作词汇表：列表行菜单与文件组网格菜单共用；标题、快捷键、⇧ 备用项只此一份。
//

import AppKit

enum ItemCommand: String, CaseIterable {
    case preview
    case paste
    case pasteAsPlainText
    case copy
    case copyAsPlainText
    case share
    case open
    case revealInFinder
    case delete

    var title: String {
        switch self {
        case .preview: Localizer.string("Preview")
        case .paste: Localizer.string("Paste")
        case .pasteAsPlainText: Localizer.string("Paste as Plain Text")
        case .copy: Localizer.string("Copy")
        case .copyAsPlainText: Localizer.string("Copy as Plain Text")
        case .share: Localizer.string("Share")
        case .open: Localizer.string("Open")
        case .revealInFinder: Localizer.string("Reveal in Finder")
        case .delete: Localizer.string("Delete")
        }
    }

    /// 菜单快捷键；仅 AppKit 行菜单使用，避免与面板按键判定语义重叠。
    var keyEquivalent: String? {
        switch self {
        case .paste, .pasteAsPlainText: "v"
        case .copy, .copyAsPlainText: "c"
        case .preview, .share, .open, .revealInFinder, .delete: nil
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .pasteAsPlainText, .copyAsPlainText: [.command, .shift]
        case .paste, .copy: .command
        case .preview, .share, .open, .revealInFinder, .delete: []
        }
    }

    var isAlternate: Bool {
        self == .pasteAsPlainText || self == .copyAsPlainText
    }

    var requiresReachableFile: Bool {
        self == .share || self == .open
    }
}

/// 菜单项：动作或分隔符；测试要构造布局，故保持 internal。
enum ItemMenuEntry: Equatable {
    case command(ItemCommand)
    case separator
}

extension ItemCommand {
    /// 列表行菜单布局：有纯文本形态的条目多两条 ⇧ 备用项，链接/图片/文件多分享与打开。
    static func rowMenuLayout(for kind: ClipboardItemKind) -> [ItemMenuEntry] {
        var entries: [ItemMenuEntry] = []
        entries.append(.command(.paste))
        if kind.hasPlainText { entries.append(.command(.pasteAsPlainText)) }
        entries.append(.command(.copy))
        if kind.hasPlainText { entries.append(.command(.copyAsPlainText)) }
        if kind != .text && kind != .color {
            entries.append(.separator)
            entries.append(.command(.share))
            entries.append(.command(.open))
        }
        entries.append(.separator)
        entries.append(.command(.delete))
        return entries
    }
}
