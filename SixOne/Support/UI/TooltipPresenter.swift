//
//  TooltipPresenter.swift
//  SixOne
//  自绘 tooltip 展示器：独立浮层窗口显示，避让屏幕边缘且不被滚动视图裁掉。

import AppKit
import SwiftUI

nonisolated enum TooltipMetrics {
    static let horizontalPadding: CGFloat = 7
    static let verticalPadding: CGFloat = 4
    static let maxBubbleWidth: CGFloat = 480
    static let shadowMargin: CGFloat = 6
    static let gapBelowPointer: CGFloat = 19
    static let gapAbovePointer: CGFloat = 17
    static let screenMargin: CGFloat = 1
    static let rehoverDistance: CGFloat = 6
}

/// 浮层窗口不抢 key/main，也不接收鼠标事件。
private final class TooltipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct TooltipLabel: View {
    let text: String
    let textWidth: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .lineLimit(nil)
            .frame(width: textWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, TooltipMetrics.horizontalPadding)
            .padding(.vertical, TooltipMetrics.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
            .padding(TooltipMetrics.shadowMargin)
    }
}

@MainActor
final class TooltipPresenter {
    static let shared = TooltipPresenter()

    /// 与系统 help tag 一致：鼠标按下、滚动或按任意键都收起（单独按修饰键不收起）。
    static let dismissEventMask: NSEvent.EventTypeMask = [
        .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown,
    ]

    private var panel: TooltipPanel?
    private var content: NSHostingView<TooltipLabel>?
    private weak var activeAnchor: NSView?
    private weak var observedWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var interactionMonitor: Any?
    private var dismissedPointer: NSPoint?
    private(set) var interactionRevision = 0

    private init() {
        interactionMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.dismissEventMask) {
            [weak self] event in
            MainActor.assumeIsolated { self?.handleInteraction() }
            return event
        }
    }

    isolated deinit {
        if let interactionMonitor {
            NSEvent.removeMonitor(interactionMonitor)
        }
    }

    func show(text: String, anchor: NSView) {
        let pointer = NSEvent.mouseLocation
        guard Self.canShow(after: dismissedPointer, at: pointer) else { return }
        dismissedPointer = nil
        present(text: text, anchor: anchor, reposition: true)
    }

    /// 最近一次收起后指针还没移开：这次 show 多半是点击/按键之后残留的调度。
    nonisolated static func canShow(after dismissed: NSPoint?, at pointer: NSPoint) -> Bool {
        guard let dismissed else { return true }
        let dx = pointer.x - dismissed.x
        let dy = pointer.y - dismissed.y
        return dx * dx + dy * dy >= TooltipMetrics.rehoverDistance * TooltipMetrics.rehoverDistance
    }

    func update(text: String, anchor: NSView) {
        present(text: text, anchor: anchor, reposition: false)
    }

    func isShowing(anchor: NSView) -> Bool {
        activeAnchor === anchor && (panel?.isVisible ?? false)
    }

    private func present(text: String, anchor: NSView, reposition: Bool) {
        guard !text.isEmpty,
              let window = anchor.window,
              window.isVisible,
              window.isKeyWindow,
              Self.isEffectivelyVisible(anchor) else {
            // 失败的是新锚点：不要顺手把另一个仍有效的 tooltip 收掉。
            if activeAnchor === anchor { hideNow() }
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        activeAnchor = anchor
        let oldFrame = panel.frame

        let textWidth = Self.textWidth(for: text)
        let label = TooltipLabel(text: text, textWidth: textWidth)
        let hosting: NSHostingView<TooltipLabel>
        if let content {
            hosting = content
            hosting.rootView = label
        } else {
            let newHosting = NSHostingView(rootView: label)
            content = newHosting
            panel.contentView = newHosting
            hosting = newHosting
        }
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: textWidth + TooltipMetrics.horizontalPadding * 2 + TooltipMetrics.shadowMargin * 2,
            height: 10
        )
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        hosting.layoutSubtreeIfNeeded()

        if reposition {
            let pointer = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
                ?? window.screen
                ?? NSScreen.main
            let visibleFrame = screen?.visibleFrame
                ?? NSRect(x: pointer.x - 200, y: pointer.y - 200, width: 400, height: 400)
            panel.setFrameOrigin(Self.origin(for: size, near: pointer, within: visibleFrame))
        } else {
            panel.setFrameOrigin(NSPoint(
                x: oldFrame.minX,
                y: oldFrame.maxY - size.height
            ))
        }
        panel.orderFrontRegardless()

        if observedWindow !== window {
            removeObservers()
            observedWindow = window
            installObservers(for: window)
        }
    }

    func hide(anchor: NSView) {
        guard activeAnchor === anchor else { return }
        hideNow()
    }

    /// 模仿系统 help tag 定位：边缘避让，下方放不下时翻到上方。
    nonisolated static func origin(
        for size: NSSize,
        near pointer: NSPoint,
        within visibleFrame: NSRect
    ) -> NSPoint {
        let margin = TooltipMetrics.screenMargin
        let shadow = TooltipMetrics.shadowMargin
        let bubbleWidth = size.width - shadow * 2
        let bubbleHeight = size.height - shadow * 2

        var bubbleX = min(pointer.x, visibleFrame.maxX - margin - bubbleWidth)
        bubbleX = max(bubbleX, visibleFrame.minX + margin)

        var bubbleY = pointer.y - TooltipMetrics.gapBelowPointer - bubbleHeight
        if bubbleY < visibleFrame.minY + margin {
            bubbleY = pointer.y + TooltipMetrics.gapAbovePointer
        }
        bubbleY = min(
            max(bubbleY, visibleFrame.minY + margin),
            visibleFrame.maxY - margin - bubbleHeight
        )
        return NSPoint(x: bubbleX - shadow, y: bubbleY - shadow)
    }

    /// 祖先被 opacity(0) 或 isHidden 隐藏时（例如打开预览后仍留在树里的列表），不要再显示 tooltip。
    static func isEffectivelyVisible(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let currentView = current {
            if currentView.isHidden || currentView.alphaValue <= 0.001 { return false }
            if let layer = currentView.layer, layer.isHidden || layer.opacity <= 0.001 { return false }
            current = currentView.superview
        }
        return true
    }

    private static func textWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11)
        let maxLineWidth = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return min(
            ceil(maxLineWidth) + 1,
            TooltipMetrics.maxBubbleWidth - TooltipMetrics.horizontalPadding * 2
        )
    }

    private func makePanel() -> TooltipPanel {
        let panel = TooltipPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func installObservers(for window: NSWindow) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.hideNow() }
            },
            center.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.hideNow() }
            },
            center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.hideNow() }
            },
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.hideNow() }
            },
        ]
    }

    private func handleInteraction() {
        interactionRevision &+= 1
        dismissedPointer = NSEvent.mouseLocation
        hideNow()
    }

    private func removeObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        observedWindow = nil
    }

    private func hideNow() {
        removeObservers()
        activeAnchor = nil
        panel?.orderOut(nil)
    }
}
