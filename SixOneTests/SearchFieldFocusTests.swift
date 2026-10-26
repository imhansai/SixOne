//
//  SearchFieldFocusTests.swift
//  SixOneTests
//  搜索框右键：先聚焦上报再弹菜单；用注入落点，避免系统菜单抢并行事件。

import AppKit
import Testing
@testable import SixOne

@Suite("搜索框右键聚焦")
@MainActor
struct SearchFieldFocusTests {
    private final class FirstResponderView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    @Test("右键菜单前把真实焦点交给搜索框并上报聚焦")
    func focusForContextMenuInstallsEditor() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let content = FirstResponderView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView = content

        let field = FocusAwareTextField(frame: NSRect(x: 40, y: 80, width: 300, height: 40))
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.stringValue = "hello"
        content.addSubview(field)

        var reports: [Bool] = []
        field.onFocusChange = { reports.append($0) }
        var menuPresentedWithEditor = false
        field.presentContextMenu = { _ in
            menuPresentedWithEditor = (field.currentEditor() != nil)
        }

        #expect(window.makeFirstResponder(content))
        #expect(window.firstResponder === content)

        let rightClick = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        field.rightMouseDown(with: rightClick)

        #expect(field.currentEditor() != nil, "没有进入编辑态")
        #expect(window.firstResponder === field.currentEditor(), "第一响应者没有落到搜索框")
        #expect(reports.contains(true), "没有上报聚焦")
        #expect(menuPresentedWithEditor, "菜单应在聚焦之后才弹出")

        let editor = field.currentEditor()
        field.focusForContextMenu()
        #expect(field.currentEditor() === editor, "重复触发不应重建 field editor")
        #expect(reports.last == true, "重复触发仍要保证聚焦状态")
    }
}
