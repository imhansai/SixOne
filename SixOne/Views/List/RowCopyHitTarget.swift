//
//  RowCopyHitTarget.swift
//  SixOne
//
//  复制按钮命中目标：盖在行宿主之上的透明视图，只收普通左键，其余放行给宿主。
//

import AppKit
import SwiftUI

struct RowCopyHitTarget: NSViewRepresentable {
    let onCopy: () -> Void

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.onCopy = onCopy
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        view.onCopy = onCopy
    }

    final class HostView: NSView {
        var onCopy: (() -> Void)?

        private var isPressed = false
        private var pressLocationInWindow: NSPoint?

        // MARK: - 命中策略

        override func hitTest(_ point: NSPoint) -> NSView? {
            // 只收普通左键，其余返回 nil 让行宿主接管菜单。
            guard let event = NSApp.currentEvent,
                  RowHitPolicy.isPlainLeftClick(event.type, modifiers: event.modifierFlags)
            else { return nil }
            return super.hitTest(point)
        }

        // MARK: - 鼠标事件

        override func mouseDown(with event: NSEvent) {
            isPressed = true
            pressLocationInWindow = event.locationInWindow
        }

        override func mouseUp(with event: NSEvent) {
            guard isPressed, let press = pressLocationInWindow else { return }
            isPressed = false
            pressLocationInWindow = nil
            // 指针自己拖出不算点击；行被应用挪走不算。
            let travel = hypot(
                event.locationInWindow.x - press.x,
                event.locationInWindow.y - press.y
            )
            guard RowHitPolicy.completesClick(
                releaseInsideRow: bounds.contains(convert(event.locationInWindow, from: nil)),
                pointerTravel: travel
            ) else { return }
            // 一次手势只复制一次，双击第二下不触发。
            guard event.clickCount == 1 else { return }
            onCopy?()
        }
    }
}
