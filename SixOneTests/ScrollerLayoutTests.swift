//
//  ScrollerLayoutTests.swift
//  SixOneTests

import AppKit
import Observation
import Testing
@testable import SixOne

@Suite("滚动条形态取值")
struct ScrollerLayoutTests {
    private func makeScrollView(style: NSScroller.Style, documentHeight: CGFloat = 4000) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: ClipboardLayout.panelSize))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = style
        scrollView.documentView = NSView(
            frame: NSRect(x: 0, y: 0, width: ClipboardLayout.panelWidth, height: documentHeight)
        )
        scrollView.tile()
        return scrollView
    }

    @Test("浮层样式：不占布局宽度，判为浮层")
    func overlayReportsOverlay() {
        let scrollView = makeScrollView(style: .overlay)
        #expect(ScrollerLayoutProbe.usesOverlayScrollers(in: scrollView))
        #expect(scrollView.contentView.frame.width == ClipboardLayout.panelWidth)
    }

    @Test("传统样式：滚动条占掉布局宽度，判为传统")
    func legacyReportsLegacy() {
        let scrollView = makeScrollView(style: .legacy)
        #expect(!ScrollerLayoutProbe.usesOverlayScrollers(in: scrollView))
        let reserved = ClipboardLayout.panelWidth - scrollView.contentView.frame.width
        #expect(reserved > 0)
        #expect(reserved >= ClipboardLayout.overlayScrollerKnobClearance)
    }

    @Test("传统样式下滚动条被自动隐藏（内容没超出）时仍按传统算")
    func hiddenLegacyScrollerStaysLegacy() {
        let scrollView = makeScrollView(style: .legacy, documentHeight: 40)
        // 滚动条被移除后 clip 铺满宽度，此时仍按传统样式。
        #expect(scrollView.contentView.frame.width == ClipboardLayout.panelWidth)
        #expect(!ScrollerLayoutProbe.usesOverlayScrollers(in: scrollView))
    }

    @Test("状态初值与滚动视图自己的样式一致")
    func initialStateMatchesScrollViewStyle() {
        let probe = NSScrollView(frame: NSRect(origin: .zero, size: ClipboardLayout.panelSize))
        #expect(
            ScrollerLayoutState().usesOverlayScrollers
                == ScrollerLayoutProbe.usesOverlayScrollers(in: probe)
        )
    }

    @Test("形态变化能被观察，行视图才会跟着重建")
    func stateChangeIsObservable() {
        let state = ScrollerLayoutState()
        nonisolated(unsafe) var notified = false
        withObservationTracking {
            _ = state.usesOverlayScrollers
        } onChange: {
            notified = true
        }
        state.usesOverlayScrollers.toggle()
        #expect(notified)
    }
}
