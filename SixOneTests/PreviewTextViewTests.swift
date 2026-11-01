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

    @Test("Esc 交回面板")
    func escapeGoesToPanel() {
        let view = makeView()
        var escaped = false
        view.onEscape = { escaped = true }

        view.cancelOperation(nil)

        #expect(escaped)
    }
}
