//
//  TooltipAnchor.swift
//  SixOne
//  SwiftUI 悬停锚点与 `.appTooltip`：用 NSTrackingArea 收事件，停稳后交给 `TooltipPresenter`。

import AppKit
import SwiftUI

struct TooltipAnchor: NSViewRepresentable {
    var onMove: (NSView) -> Void = { _ in }
    let onHover: (Bool, NSView) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: TrackingView) {
        view.onMove = onMove
        view.onHover = onHover
    }

    final class TrackingView: NSView {
        var onMove: ((NSView) -> Void)?
        var onHover: ((Bool, NSView) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: .zero,
                options: [
                    .mouseEnteredAndExited,
                    .mouseMoved,
                    .activeInKeyWindow,
                    .inVisibleRect,
                ],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(true, self)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false, self)
        }

        override func mouseMoved(with event: NSEvent) {
            onMove?(self)
        }

        /// 视图在指针下方创建时补一次进入（行复用、标题刚被截断）。
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                guard self.bounds.contains(point) else { return }
                self.onHover?(true, self)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct AppTooltipModifier: ViewModifier {
    let text: String

    @State private var isHovered = false
    @State private var anchorView: NSView?
    @State private var showWork: DispatchWorkItem?
    @State private var lastScheduleLocation: NSPoint?

    private static let showDelay: TimeInterval = 0.3
    private static let movementThreshold: CGFloat = 2

    func body(content: Content) -> some View {
        content
            .background(
                TooltipAnchor(
                    onMove: { view in
                        handleMove(view)
                    }
                ) { hovering, view in
                    handleHover(hovering, view: view)
                }
            )
            .accessibilityHint(Text(text))
            .onChange(of: text) { _, newValue in
                handleTextChange(newValue)
            }
            .onDisappear {
                cancelShow()
                if let anchorView {
                    TooltipPresenter.shared.hide(anchor: anchorView)
                }
                isHovered = false
                anchorView = nil
            }
    }

    private func handleHover(_ hovering: Bool, view: NSView) {
        if hovering {
            isHovered = true
            anchorView = view
            scheduleShow(view: view)
        } else {
            isHovered = false
            cancelShow()
            TooltipPresenter.shared.hide(anchor: view)
        }
    }

    private func handleMove(_ view: NSView) {
        guard isHovered, !TooltipPresenter.shared.isShowing(anchor: view) else { return }
        let pointer = NSEvent.mouseLocation
        if let last = lastScheduleLocation {
            let distance = hypot(pointer.x - last.x, pointer.y - last.y)
            guard distance >= Self.movementThreshold else { return }
        }
        scheduleShow(view: view)
    }

    private func handleTextChange(_ newValue: String) {
        guard isHovered, let anchorView else { return }
        if TooltipPresenter.shared.isShowing(anchor: anchorView) {
            TooltipPresenter.shared.update(text: newValue, anchor: anchorView)
        } else {
            scheduleShow(view: anchorView)
        }
    }

    private func scheduleShow(view: NSView) {
        guard !TooltipPresenter.shared.isShowing(anchor: view) else { return }
        showWork?.cancel()
        lastScheduleLocation = NSEvent.mouseLocation
        let revision = TooltipPresenter.shared.interactionRevision
        let work = DispatchWorkItem {
            guard isHovered, TooltipPresenter.shared.interactionRevision == revision else { return }
            TooltipPresenter.shared.show(text: text, anchor: view)
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
    }

    private func cancelShow() {
        showWork?.cancel()
        showWork = nil
        lastScheduleLocation = nil
    }
}

extension View {
    /// 自绘即时 tooltip，替代系统 `.help`。
    func appTooltip(_ text: String) -> some View {
        modifier(AppTooltipModifier(text: text))
    }

    @ViewBuilder
    func appTooltipIf(_ condition: Bool, text: String) -> some View {
        if condition {
            appTooltip(text)
        } else {
            self
        }
    }
}
