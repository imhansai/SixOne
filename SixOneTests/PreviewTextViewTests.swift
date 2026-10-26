//
//  PreviewTextViewTests.swift
//  SixOneTests

import AppKit
import Testing
@testable import SixOne

@Suite("预览正文 NSTextView")
@MainActor
struct PreviewTextViewTests {
    private func makeView(editable: Bool = false) -> PreviewTextView {
        let view = PreviewTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        view.string = "hello"
        view.isEditable = editable
        view.isSelectable = true
        view.setSelectedRange(NSRange(location: 0, length: 0))
        return view
    }

    @Test("只读、无选区：⌘C 走整条兜底")
    func copyWithoutSelectionFallsBack() {
        let view = makeView()
        var copied = false
        view.onCopyFallback = { copied = true }

        view.copy(nil)

        #expect(copied)
    }

    @Test("编辑态、无选区：不触发整条兜底")
    func editingDoesNotFallBack() {
        let view = makeView(editable: true)
        var copied = false
        view.onCopyFallback = { copied = true }

        view.copy(nil)

        #expect(!copied)
    }

    @Test("只读、⌘V：走整条粘贴兜底")
    func pasteWithoutEditingFallsBack() {
        let view = makeView()
        var pasted = false
        view.onPasteFallback = { pasted = true }

        view.paste(nil)

        #expect(pasted)
    }

    @Test("菜单校验：只读 Paste 仍然可用，兜底才有入口")
    func validatesPasteWithoutSelection() {
        let view = makeView()
        view.onPasteFallback = {}
        let item = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

        #expect(view.validateUserInterfaceItem(item))
        #expect(view.validateMenuItem(item), "fallback 的 validateMenuItem 也要放行")
    }

    @Test("Esc 交回面板")
    func escapeGoesToPanel() {
        let view = makeView()
        var escaped = false
        view.onEscape = { escaped = true }

        view.cancelOperation(nil)

        #expect(escaped)
    }

    @Test("菜单校验：无选区的只读 Copy 仍然可用，兜底才有入口")
    func validatesCopyWithoutSelection() {
        let view = makeView()
        view.onCopyFallback = {}
        let item = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")

        #expect(view.validateUserInterfaceItem(item))
        #expect(view.validateMenuItem(item), "fallback 的 validateMenuItem 也要放行")
    }
}
