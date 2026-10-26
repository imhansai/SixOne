//
//  TooltipPresenterTests.swift
//  SixOneTests

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("Tooltip 定位")
struct TooltipPresenterTests {
    private let screen = NSRect(x: 0, y: 0, width: 800, height: 1000)
    private let size = NSSize(width: 112, height: 32)

    @Test("左边缘对齐指针，顶部在指针下方 19pt")
    func placesBelowPointer() {
        let origin = TooltipPresenter.origin(
            for: size,
            near: NSPoint(x: 200, y: 500),
            within: screen
        )
        #expect(origin == NSPoint(x: 194, y: 455))
    }

    @Test("下方放不下时翻到上方，间隔 17pt")
    func flipsAbove() {
        let origin = TooltipPresenter.origin(
            for: size,
            near: NSPoint(x: 200, y: 10),
            within: screen
        )
        #expect(origin == NSPoint(x: 194, y: 21))
    }

    @Test("右边放不下时向左滑到屏幕内")
    func slidesLeftAtScreenEdge() {
        let origin = TooltipPresenter.origin(
            for: size,
            near: NSPoint(x: 750, y: 500),
            within: screen
        )
        #expect(origin == NSPoint(x: 693, y: 455))
    }

    @Test("气泡变高时向下展开，顶部位置不变")
    func growsDownwardFromFixedTop() {
        let pointer = NSPoint(x: 200, y: 500)
        let short = TooltipPresenter.origin(for: size, near: pointer, within: screen)
        let tall = TooltipPresenter.origin(
            for: NSSize(width: 112, height: 60),
            near: pointer,
            within: screen
        )
        #expect(tall.x == short.x)
        #expect(tall.y == short.y - 28)
    }

    @Test("按键、点击与滚动会收起 tooltip，单独按修饰键不会")
    @MainActor
    func dismissesOnInteraction() {
        #expect(TooltipPresenter.dismissEventMask.contains(.keyDown))
        #expect(TooltipPresenter.dismissEventMask.contains(.leftMouseDown))
        #expect(TooltipPresenter.dismissEventMask.contains(.scrollWheel))
        #expect(!TooltipPresenter.dismissEventMask.contains(.flagsChanged))
    }

    @Test("收起后指针没移开时，残留的 show 请求不会再弹 tooltip")
    func suppressesShowUntilPointerMoves() {
        let dismissed = NSPoint(x: 200, y: 500)
        #expect(!TooltipPresenter.canShow(after: dismissed, at: NSPoint(x: 203, y: 502)))
        #expect(TooltipPresenter.canShow(after: dismissed, at: NSPoint(x: 210, y: 500)))
        #expect(TooltipPresenter.canShow(after: nil, at: dismissed))
    }

    @Test("祖先透明或隐藏时不再显示 tooltip")
    @MainActor
    func ignoresHiddenAnchors() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let child = NSView(frame: NSRect(x: 10, y: 10, width: 20, height: 20))
        parent.addSubview(child)

        #expect(TooltipPresenter.isEffectivelyVisible(child))
        parent.alphaValue = 0
        #expect(!TooltipPresenter.isEffectivelyVisible(child))
        parent.alphaValue = 1
        parent.isHidden = true
        #expect(!TooltipPresenter.isEffectivelyVisible(child))
    }

    @Test("tooltip 内容按完整文本撑开，长文本换行")
    @MainActor
    func labelSizesToFullText() {
        func fittingSize(_ text: String, textWidth: CGFloat) -> NSSize {
            let host = NSHostingView(rootView: TooltipLabel(text: text, textWidth: textWidth))
            host.frame = NSRect(x: 0, y: 0, width: textWidth + 26, height: 10)
            host.layoutSubtreeIfNeeded()
            return host.fittingSize
        }

        let short = fittingSize("Reveal in Finder", textWidth: 200)
        #expect(short.width >= 200)
        #expect(short.height >= 20)

        let long = fittingSize(
            String(repeating: "很长的标题", count: 30) + ".txt",
            textWidth: 466
        )
        #expect(long.width >= 466)
        #expect(long.height > 40, "长文本没有换行，tooltip 会被截断")
    }
}
