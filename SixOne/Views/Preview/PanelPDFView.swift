//
//  PanelPDFView.swift
//  SixOne
//
//  PDFView 子类：无选区时 ⌘C 交回面板复制整条，有选区走系统 copy:。
//

import AppKit
import PDFKit

final class PanelPDFView: PDFView {
    var onCopyFallback: (() -> Void)?

    override func copy(_ sender: Any?) {
        if (currentSelection?.string ?? "").isEmpty, let onCopyFallback {
            onCopyFallback()
            return
        }
        super.copy(sender)
    }
}
