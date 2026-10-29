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
    /// 按下状态用于按钮高亮；取消或移除时复位。
    var onPressChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.onCopy = onCopy
        view.onPressChanged = onPressChanged
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        view.onCopy = onCopy
        view.onPressChanged = onPressChanged
    }

    final class HostView: NSView {
        var onCopy: (() -> Void)?
        var onPressChanged: ((Bool) -> Void)?

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
            onPressChanged?(true)
        }

        override func mouseUp(with event: NSEvent) {
            defer { releasePress() }
            guard isPressed, let press = pressLocationInWindow else { return }
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

        /// 行被回收或挪走时也要复位，避免高亮卡住。
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { releasePress() }
        }

        private func releasePress() {
            guard isPressed else { return }
            isPressed = false
            pressLocationInWindow = nil
            onPressChanged?(false)
        }
    }
}
