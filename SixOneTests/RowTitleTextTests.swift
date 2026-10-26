//
//  RowTitleTextTests.swift
//  SixOneTests

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("标题截断才显示 tooltip")
@MainActor
struct RowTitleTextTests {
    private func makeHost(text: String, width: CGFloat) -> (NSHostingView<AnyView>, NSWindow) {
        let view = AnyView(
            RowTitleText(text: text, isActiveSelection: false)
                .frame(width: width)
        )
        let (host, window) = OffscreenHost.make(view, size: NSSize(width: 400, height: 80))
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    private func trackingViewCount(in host: NSView) -> Int {
        OffscreenHost.allSubviews(of: host)
            .compactMap { $0 as? TooltipAnchor.TrackingView }
            .count
    }

    @Test("长标题被截断时挂 tooltip")
    func truncatedTitleHasTooltip() async {
        let (host, window) = makeHost(
            text: "这是一个非常非常长的文件名，用来确认标题被截断后才显示 tooltip.txt",
            width: 120
        )
        defer { window.orderOut(nil) }

        let mounted = await Wait.until(timeout: .seconds(2)) {
            trackingViewCount(in: host) > 0
        }
        #expect(mounted, "长标题被截断后没有挂 tooltip")
    }

    @Test("短标题完全显示时不挂 tooltip")
    func fittingTitleHasNoTooltip() async {
        let (host, window) = makeHost(text: "短标题", width: 300)
        defer { window.orderOut(nil) }

        await Wait.settle(milliseconds: 150)
        #expect(trackingViewCount(in: host) == 0, "标题完全显示却挂了 tooltip")
    }
}
