//
//  RowInteractionHost.swift
//  SixOne
//

import AppKit
import SwiftUI

// MARK: - 行交互宿主

/// 菜单动作持有者：闭包挂在这里随菜单项同生共死（`target` 是弱引用）。
final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func run() {
        handler()
    }
}

/// 行鼠标交互入口：覆盖整行的透明视图，独占左键与右键。
/// 单击在 mouseUp 落定；手势状态由列表持有，行视图回收不影响。不要改用 SwiftUI tap 手势。
struct RowInteractionHost: NSViewRepresentable {
    let rowID: UUID
    let onSelect: (UUID) -> Void
    /// 参数是连击序列起点的条目 id；第二参数表示按住 ⇧ 的纯文本意图。
    let onActivate: (UUID, Bool) -> Void
    let makeMenu: (HostView) -> NSMenu?
    var clickTracker: RowClickTracker?

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        configure(view)
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        configure(view)
    }

    private func configure(_ view: HostView) {
        view.currentRowID = rowID
        view.makeMenu = makeMenu
        view.clickTracker = clickTracker
        view.localClickTracker.onSelect = onSelect
        view.localClickTracker.onActivate = onActivate
    }

    final class HostView: NSView {
        var currentRowID = UUID()
        var makeMenu: ((HostView) -> NSMenu?)?
        var clickTracker: RowClickTracker?
        let localClickTracker = RowClickTracker()

        private var activeTracker: RowClickTracker { clickTracker ?? localClickTracker }

        // MARK: - 命中策略

        override func hitTest(_ point: NSPoint) -> NSView? {
            // 只对鼠标事件参与命中测试，其余事件穿透。
            guard let event = NSApp.currentEvent,
                  RowHitPolicy.claims(type: event.type) else { return nil }
            return super.hitTest(point)
        }

        // MARK: - 鼠标事件

        override func mouseDown(with event: NSEvent) {
            // ⌃+左键按菜单语义处理，AppKit 不一定转成 rightMouseDown。
            guard event.modifierFlags.contains(.control) else {
                activeTracker.begin(rowID: currentRowID, event: event)
                return
            }
            presentMenu(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            let release = convert(event.locationInWindow, from: nil)
            activeTracker.end(event: event, releaseInsideRow: bounds.contains(release))
        }

        override func rightMouseDown(with event: NSEvent) {
            presentMenu(with: event)
        }

        @objc func performMenuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? MenuAction)?.run()
        }

        private func presentMenu(with event: NSEvent) {
            guard let menu = makeMenu?(self) else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}

/// 行点击手势状态：列表持有一份、所有行宿主共用；行视图被回收/重建不影响结果。
@MainActor
final class RowClickTracker {
    var onSelect: ((UUID) -> Void)?
    var onActivate: ((UUID, Bool) -> Void)?

    /// 按下时记下的条目 id；抬起落到复用宿主上也仍选按下的那条。
    private(set) var pressedRowID: UUID?
    private var pressLocationInWindow: NSPoint?
    private var sequenceRowID: UUID?
    private var sequenceStartTimestamp: TimeInterval?

    func cancel() {
        pressedRowID = nil
        pressLocationInWindow = nil
    }

    func begin(rowID: UUID, event: NSEvent) {
        pressedRowID = rowID
        pressLocationInWindow = event.locationInWindow
        if event.clickCount == 1 {
            sequenceRowID = rowID
            sequenceStartTimestamp = event.timestamp
        } else if let start = sequenceStartTimestamp,
                  event.timestamp - start > NSEvent.doubleClickInterval {
            sequenceRowID = nil
        }
    }

    /// 抬起：完成点击；位移按按下时位置算，宿主被重建也不影响。
    func end(event: NSEvent, releaseInsideRow: Bool) {
        guard let pressedRowID, let press = pressLocationInWindow else { return }
        self.pressedRowID = nil
        pressLocationInWindow = nil
        let travel = hypot(
            event.locationInWindow.x - press.x,
            event.locationInWindow.y - press.y
        )
        guard RowHitPolicy.completesClick(
            releaseInsideRow: releaseInsideRow,
            pointerTravel: travel
        ) else { return }
        switch event.clickCount {
        case 0, 1:
            // 单击选中；clickCount 0 来自异常事件，按单击兜底别吞掉选中。
            onSelect?(pressedRowID)
        case 2:
            onActivate?(sequenceRowID ?? pressedRowID, event.modifierFlags.contains(.shift))
        default:
            // 三连击不再叠加，避免一次手势粘贴多次。
            break
        }
    }
}

/// 命中策略：哪些事件归行宿主、哪些归复制命中目标。纯值判定，便于单测。
enum RowHitPolicy {
    /// 指针位移容差：应用滚走行导致的位移不算拖出。
    static let clickPointerSlop: CGFloat = 4

    static func completesClick(releaseInsideRow: Bool, pointerTravel: CGFloat) -> Bool {
        releaseInsideRow || pointerTravel <= clickPointerSlop
    }

    static func claims(type: NSEvent.EventType) -> Bool {
        isMouseEvent(type)
    }

    static func isMouseEvent(_ type: NSEvent.EventType) -> Bool {
        switch type {
        case .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    /// 普通左键：左键且不带 ⌃（带 ⌃ 按右键处理）。
    static func isPlainLeftClick(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch type {
        case .leftMouseDown, .leftMouseUp:
            return !modifiers.contains(.control)
        default:
            return false
        }
    }
}
