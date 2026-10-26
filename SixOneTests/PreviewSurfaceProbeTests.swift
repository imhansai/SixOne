//
//  PreviewSurfaceProbeTests.swift
//  SixOneTests

import AppKit
import PDFKit
import QuickLookUI
import Testing
@testable import SixOne

@Suite("预览表面探针")
@MainActor
struct PreviewSurfaceProbeTests {
    @Test("在视图树里按标识找到预览正文视图，忽略别的文本视图")
    func findsPreviewTextViewByIdentifier() throws {
        let root = NSView()
        let unrelated = NSTextView()
        unrelated.identifier = NSUserInterfaceItemIdentifier("some.other.text")
        let preview = NSTextView()
        preview.identifier = TextPreviewView.textViewIdentifier
        let nested = NSView()
        nested.addSubview(preview)
        root.addSubview(unrelated)
        root.addSubview(nested)

        let probe = PreviewSurfaceProbe(contentView: root, firstResponder: nil)
        #expect(probe.previewTextView() === preview)
    }

    @Test("视图树里没有预览正文时返回 nil（而不是随便找一个文本视图）")
    func returnsNilWithoutPreviewTextView() {
        let root = NSView()
        root.addSubview(NSTextView())

        let probe = PreviewSurfaceProbe(contentView: root, firstResponder: nil)
        #expect(probe.previewTextView() == nil)
    }

    @Test("第一响应者是预览正文时，能读出焦点与选中长度")
    func readsFocusAndSelectionFromPreviewTextView() {
        let textView = NSTextView()
        textView.identifier = TextPreviewView.textViewIdentifier
        textView.string = "选中的文字"
        textView.setSelectedRange(NSRange(location: 0, length: 3))

        let probe = PreviewSurfaceProbe(contentView: nil, firstResponder: textView)
        #expect(probe.isFocusedOnPreviewText)
        #expect(probe.previewTextSelectionLength == 3)
    }

    @Test("按标识找到文件组筛选框，并据第一响应者判定聚焦")
    func findsGroupFilterFieldFocus() {
        let root = NSView()
        let field = NSTextField()
        field.identifier = .groupFilterField
        root.addSubview(field)

        let focused = PreviewSurfaceProbe(contentView: root, firstResponder: field)
        #expect(focused.groupFilterField() === field)
        #expect(focused.isFocusedOnGroupFilter)

        let elsewhere = PreviewSurfaceProbe(contentView: root, firstResponder: NSTextView())
        #expect(elsewhere.groupFilterField() === field)
        #expect(!elsewhere.isFocusedOnGroupFilter)
    }

    @Test("第一响应者不是预览正文时，焦点判定为假")
    func doesNotClaimFocusForOtherResponder() {
        let searchField = NSTextView()
        searchField.identifier = NSUserInterfaceItemIdentifier("search.field")

        let probe = PreviewSurfaceProbe(contentView: nil, firstResponder: searchField)
        #expect(!probe.isFocusedOnPreviewText)
    }

    @Test("顺着父视图链找到 PDF 视图")
    func findsPDFViewUpTheSuperviewChain() throws {
        let pdfView = PDFView()
        let inner = NSView()
        pdfView.addSubview(inner)
        let focused = NSView()
        inner.addSubview(focused)

        let probe = PreviewSurfaceProbe(contentView: pdfView, firstResponder: focused)
        #expect(probe.pdfView() === pdfView)
    }

    @Test("第一响应者不在 PDF 视图里时为空")
    func reportsNoPDFViewOutsidePDF() {
        let root = NSView()
        let focused = NSView()
        root.addSubview(focused)

        let probe = PreviewSurfaceProbe(contentView: root, firstResponder: focused)
        #expect(probe.pdfView() == nil)
    }

    @Test("在视图树里找到 Quick Look 预览视图（收起面板要摘掉它正在播的影片）")
    func findsQuickLookView() throws {
        let root = NSView()
        let nested = NSView()
        let preview = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        root.addSubview(nested)
        nested.addSubview(preview)

        let probe = PreviewSurfaceProbe(contentView: root, firstResponder: nil)
        #expect(probe.quickLookView() === preview)
    }

    @Test("没有 Quick Look 预览时不误报")
    func reportsNoQuickLookView() {
        let root = NSView()
        root.addSubview(NSView())

        let probe = PreviewSurfaceProbe(contentView: root, firstResponder: nil)
        #expect(probe.quickLookView() == nil)
    }

    @Test("视图树为空时各查询都安全返回空值")
    func handlesMissingContentView() {
        let probe = PreviewSurfaceProbe(contentView: nil, firstResponder: nil)
        #expect(probe.previewTextView() == nil)
        #expect(probe.quickLookView() == nil)
        #expect(probe.pdfView() == nil)
        #expect(!probe.isFindBarVisible)
        #expect(!probe.isFocusedOnPreviewText)
        #expect(!probe.isWebFocused)
        #expect(!probe.isQuickLookFocused)
    }
}
