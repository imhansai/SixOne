//
//  ClipboardPanelWindow.swift
//  SixOne

import AppKit
import SwiftUI

/// 面板窗口的键盘/收起落点；抽成协议便于脱离控制器单测。
@MainActor
protocol PanelKeyHandling: AnyObject {
    func handlePreDispatchKey(_ event: NSEvent) -> Bool
    /// 修饰键按下/松开：⌘ 按住时显示快速粘贴编号。
    func handleModifierFlagsChanged(_ event: NSEvent)
    /// AppKit 未走 key equivalent 时的命令键补充分发（只认主菜单快捷键）。
    func handleCommandKey(_ event: NSEvent) -> Bool
    func shouldUseDefaultKeyDown(for event: NSEvent) -> Bool
    var shouldCycleFocusWithTab: Bool { get }
    func cycleFocus(backwards: Bool)
    func handleEscape()
    /// ⌘W / Close Window：编辑中先取消编辑，否则收起面板。
    func handleCloseWindow()
}

/// 无边框、不激活应用的浮层面板。
final class ClipboardPanel: NSPanel {
    weak var keyHandler: PanelKeyHandling?

    override var canBecomeKey: Bool { true }
    /// 让面板能成为 main（NSPanel 默认被排除）；须先可见再 makeMain，否则激活前移的是设置窗口。
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            keyHandler?.handleModifierFlagsChanged(event)
        }
        if event.type == .keyDown, let keyHandler {
            if keyHandler.handlePreDispatchKey(event) { return }
            if keyHandler.handleCommandKey(event) { return }
        }
        super.sendEvent(event)
    }

    /// ⌘F 先交给面板路由，不认时再回菜单/响应链。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard event.type == .keyDown,
              event.keyCode == PanelKeyCode.f,
              modifiers == [.command],
              let keyHandler else {
            return super.performKeyEquivalent(with: event)
        }
        if keyHandler.handlePreDispatchKey(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// 未处理的键交给输入管理器翻译成标准 action，由控制器响应。
    override func keyDown(with event: NSEvent) {
        guard let keyHandler else {
            super.keyDown(with: event)
            return
        }
        if keyHandler.shouldUseDefaultKeyDown(for: event) {
            super.keyDown(with: event)
        } else {
            interpretKeyEvents([event])
        }
    }

    override func selectNextKeyView(_ sender: Any?) {
        guard let keyHandler, keyHandler.shouldCycleFocusWithTab else {
            super.selectNextKeyView(sender)
            return
        }
        keyHandler.cycleFocus(backwards: false)
    }

    override func selectPreviousKeyView(_ sender: Any?) {
        guard let keyHandler, keyHandler.shouldCycleFocusWithTab else {
            super.selectPreviousKeyView(sender)
            return
        }
        keyHandler.cycleFocus(backwards: true)
    }

    override func cancelOperation(_ sender: Any?) {
        keyHandler?.handleEscape()
    }

    /// 菜单 Close Window（⌘W）收起面板而非真正 close，保持挂起语义。
    override func performClose(_ sender: Any?) {
        guard let keyHandler else {
            super.performClose(sender)
            return
        }
        keyHandler.handleCloseWindow()
    }

    /// 面板没有 `.closable`，但 performClose 已改成收起，这里放行菜单校验。
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(NSWindow.performClose(_:)) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(NSWindow.performClose(_:)) {
            return true
        }
        return super.validateMenuItem(menuItem)
    }
}

/// 顶栏空白处的拖拽把手：窗口关闭了系统拖拽，由这一层发起。
struct PanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        /// 把 mouseDown 交给 Window Server 拖动窗口（公开 API，10.11+）。
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
