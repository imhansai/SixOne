//
//  PanelMenuCommandTable.swift
//  SixOne
//  面板菜单命令的唯一元数据：selector、标题、菜单键位与可用性命令。
//

import AppKit

struct PanelMenuCommandInfo {
    let command: PanelMenuCommand
    let selector: Selector
    let title: String
    let key: String
    let modifiers: NSEvent.ModifierFlags
}

/// 主菜单仍由 `MainMenuBuilder` 显式搭树；这里只提供命令项自身的元数据。
@MainActor
enum PanelMenuCommandTable {
    static let entries: [PanelMenuCommandInfo] = [
        entry(.copy, #selector(ClipboardPanelController.copy(_:)), "Copy", "c", [.command]),
        entry(.paste, #selector(ClipboardPanelController.paste(_:)), "Paste", "v", [.command]),
        entry(.copyAsPlainText, #selector(ClipboardPanelController.copyAsPlainText(_:)), "Copy as Plain Text", "c", [.command, .shift]),
        entry(.pasteAsPlainText, #selector(ClipboardPanelController.pasteAsPlainText(_:)), "Paste as Plain Text", "v", [.command, .shift]),
        entry(.delete, #selector(ClipboardPanelController.delete(_:)), "Delete", "\u{7f}", [.command]),
        entry(.preview, #selector(ClipboardPanelController.previewSelectedItem(_:)), "Preview", "", []),
        entry(.saveEditing, #selector(ClipboardPanelController.saveEditing(_:)), "Save", "s", [.command]),
        entry(.open, #selector(ClipboardPanelController.openSelectedItem(_:)), "Open", "o", [.command]),
        entry(.reveal, #selector(ClipboardPanelController.revealSelectedItem(_:)), "Reveal in Finder", "r", [.command, .shift]),
        entry(.share, #selector(ClipboardPanelController.shareSelectedItem(_:)), "Share…", "", []),
        entry(.clearHistory, #selector(ClipboardPanelController.clearHistory(_:)), "Clear History…", "", []),
        entry(.focusSearch, #selector(ClipboardPanelController.focusSearch(_:)), "Search Clipboard", "f", [.command, .option]),
    ]

    static func entry(for command: PanelMenuCommand) -> PanelMenuCommandInfo {
        guard let entry = entries.first(where: { $0.command == command }) else {
            preconditionFailure("缺少面板命令表项：\(command)")
        }
        return entry
    }

    static func command(for selector: Selector?) -> PanelMenuCommand? {
        guard let selector else { return nil }
        return entries.first(where: { $0.selector == selector })?.command
    }

    private static func entry(
        _ command: PanelMenuCommand,
        _ selector: Selector,
        _ title: String.LocalizationValue,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags
    ) -> PanelMenuCommandInfo {
        PanelMenuCommandInfo(
            command: command,
            selector: selector,
            title: Localizer.string(title),
            key: key,
            modifiers: modifiers
        )
    }
}
