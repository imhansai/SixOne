//
//  PreviewSurfaceProbe.swift
//  SixOne
//  预览表面探针：从视图树里找文本视图、PDF/Web/Quick Look 与筛选框。

import AppKit
import PDFKit
import QuickLookUI
import WebKit

struct PreviewSurfaceProbe {
    let contentView: NSView?
    let firstResponder: NSResponder?

    /// 按 `TextPreviewView.textViewIdentifier` 认。
    func previewTextView() -> NSTextView? {
        guard let contentView else { return nil }
        return Self.findPreviewTextView(in: contentView)
    }

    var isFindBarVisible: Bool {
        previewTextView()?.enclosingScrollView?.isFindBarVisible ?? false
    }

    var isFocusedOnPreviewText: Bool {
        guard let textView = firstResponder as? NSTextView else { return false }
        return textView.identifier == TextPreviewView.textViewIdentifier
    }

    var previewTextSelectionLength: Int {
        (firstResponder as? NSTextView)?.selectedRange().length ?? 0
    }

    /// PDFView 不在 NSText 响应链上，只能顺着父视图找。
    func pdfView() -> PDFView? {
        guard let firstResponder = firstResponder as? NSView else { return nil }
        var view: NSView? = firstResponder
        while let current = view {
            if let pdfView = current as? PDFView { return pdfView }
            view = current.superview
        }
        return nil
    }

    var isQuickLookFocused: Bool {
        var current = firstResponder
        while let responder = current {
            if responder is QLPreviewView { return true }
            current = responder.nextResponder
        }
        return false
    }

    func groupFilterField() -> NSTextField? {
        guard let contentView else { return nil }
        return Self.findTextField(in: contentView, identifier: .groupFilterField)
    }

    /// 含 field editor 接管的情况；用现场而非状态标记，避免滞后的焦点状态误吞 ⌘F。
    var isFocusedOnGroupFilter: Bool {
        guard let field = groupFilterField() else { return false }
        if firstResponder === field { return true }
        guard let editor = field.currentEditor() else { return false }
        return firstResponder === editor
    }

    var isWebFocused: Bool {
        guard let firstResponder = firstResponder as? NSView else { return false }
        var view: NSView? = firstResponder
        while let current = view {
            if current is WKWebView { return true }
            view = current.superview
        }
        return false
    }

    func quickLookView() -> QLPreviewView? {
        guard let contentView else { return nil }
        return Self.findQuickLookView(in: contentView)
    }

    // MARK: - 递归查找

    private static func findPreviewTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView,
           textView.identifier == TextPreviewView.textViewIdentifier {
            return textView
        }
        for subview in view.subviews {
            if let found = findPreviewTextView(in: subview) { return found }
        }
        return nil
    }

    private static func findTextField(
        in view: NSView,
        identifier: NSUserInterfaceItemIdentifier
    ) -> NSTextField? {
        if let field = view as? NSTextField, field.identifier == identifier {
            return field
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview, identifier: identifier) { return found }
        }
        return nil
    }

    private static func findQuickLookView(in view: NSView) -> QLPreviewView? {
        if let previewView = view as? QLPreviewView { return previewView }
        for subview in view.subviews {
            if let found = findQuickLookView(in: subview) { return found }
        }
        return nil
    }
}
