//
//  PreviewTextView.swift
//  SixOne
//
//  NSTextView 子类：只读态下 ⌘C/⌘V 与 Esc 交回面板处理。
//

import AppKit

final class PreviewTextView: NSTextView {
    /// 只读且无选区时 ⌘C：由面板复制整条条目。
    var onCopyFallback: (() -> Void)?
    var onPasteFallback: (() -> Void)?
    var onEscape: (() -> Void)?

    override func copy(_ sender: Any?) {
        if !isEditable, selectedRange().length == 0, let onCopyFallback {
            onCopyFallback()
            return
        }
        super.copy(sender)
    }

    override func paste(_ sender: Any?) {
        if !isEditable, let onPasteFallback {
            onPasteFallback()
            return
        }
        super.paste(sender)
    }

    override func cancelOperation(_ sender: Any?) {
        if let onEscape {
            onEscape()
            return
        }
        super.cancelOperation(sender)
    }

    /// 让无选区时的 Copy 菜单项保持可用，copy: 才能走兜底。
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(NSText.copy(_:)),
           !isEditable,
           selectedRange().length == 0,
           onCopyFallback != nil {
            return true
        }
        if item.action == #selector(NSText.paste(_:)),
           !isEditable,
           onPasteFallback != nil {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}
