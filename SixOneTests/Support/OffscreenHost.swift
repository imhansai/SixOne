//
//  OffscreenHost.swift
//  SixOneTests
//
//  离屏托管与视图树探针：在屏幕外窗口跑真实装配，再从视图树取部件。
//

import AppKit
import SwiftUI

@MainActor
enum OffscreenHost {
    /// 建一个屏幕外的托管窗口。
    static func make(_ view: AnyView, size: NSSize) -> (host: NSHostingView<AnyView>, window: NSWindow) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFrontRegardless()
        return (host, window)
    }

    /// 视图树里的全部子视图。
    static func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews(of:))
    }

    static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }

    /// 轮询等 SwiftUI 建出滚动视图。
    static func waitForScrollView(in host: NSView, timeout: Duration = .seconds(5)) async -> NSScrollView? {
        await Wait.until(timeout: timeout) { findScrollView(in: host) != nil }
        return findScrollView(in: host)
    }

    /// 文档顶边到可视区顶边的距离。
    static func offsetFromTop(_ scrollView: NSScrollView) -> CGFloat {
        let visible = scrollView.documentVisibleRect
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        return scrollView.documentView?.isFlipped == true
            ? visible.minY
            : documentHeight - visible.maxY
    }
}
