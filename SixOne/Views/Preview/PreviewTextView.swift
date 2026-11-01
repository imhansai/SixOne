//
//  PreviewTextView.swift
//  SixOne
//
//  NSTextView 子类：只读态下 Esc 交回面板处理，复制/粘贴保持系统默认。
//

import AppKit

final class PreviewTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        if let onEscape {
            onEscape()
            return
        }
        super.cancelOperation(sender)
    }
}
