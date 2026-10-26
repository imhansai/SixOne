//
//  ScrollerLayout.swift
//  SixOne
//  列表滚动条形态；浮层样式不占布局宽度，行尾需相应让位。

import AppKit
import Observation

/// `HistoryListTableView` 写、行视图读；不用 `preferredScrollerStyle`，避免启动早期取值未解析。
@Observable
final class ScrollerLayoutState {
    var usesOverlayScrollers = ScrollerLayoutState.probeUsesOverlayScrollers()

    /// 初值用临时滚动视图探测，真实值随后由列表发布。
    private static func probeUsesOverlayScrollers() -> Bool {
        ScrollerLayoutProbe.usesOverlayScrollers(
            in: NSScrollView(frame: NSRect(origin: .zero, size: ClipboardLayout.panelSize))
        )
    }
}

/// 读实例的 `scrollerStyle`，AppKit 会在偏好变化时更新。
enum ScrollerLayoutProbe {
    static func usesOverlayScrollers(in scrollView: NSScrollView) -> Bool {
        scrollView.scrollerStyle == .overlay
    }
}
