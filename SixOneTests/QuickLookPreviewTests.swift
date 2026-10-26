//
//  QuickLookPreviewTests.swift
//  SixOneTests

import AppKit
import QuickLookUI
import SwiftUI
import Testing
@testable import SixOne

@Suite("Quick Look 预览宿主")
@MainActor
struct QuickLookPreviewTests {
    @Test("影片按比例居中，画面外留给面板自己的底", arguments: [
        (16.0 / 9.0, NSRect(x: 0, y: 87.5, width: 400, height: 225)),
        (9.0 / 16.0, NSRect(x: 87.5, y: 0, width: 225, height: 400)),
        (1.0, NSRect(x: 0, y: 0, width: 400, height: 400)),
    ])
    func fitsMovieAspect(aspect: CGFloat, expected: NSRect) {
        let host = hostView(aspect: aspect)

        #expect(previewView(in: host)?.frame == expected)
    }

    @Test("比例未知（非影片）时铺满")
    func fillsWithoutAspect() {
        let host = hostView(aspect: nil)

        #expect(previewView(in: host)?.frame == host.bounds)
    }

    @Test("换比例只重摆，不重装预览项")
    func relayoutKeepsPreviewItem() {
        let host = hostView(aspect: 16.0 / 9.0)
        let item = previewView(in: host)?.previewItem as? NSURL

        host.show(url: movieURL, videoAspect: 4.0 / 3.0)
        host.layoutSubtreeIfNeeded()

        #expect(previewView(in: host)?.previewItem as? NSURL == item)
        #expect(previewView(in: host)?.frame == NSRect(x: 0, y: 50, width: 400, height: 300))
    }

    @Test("SwiftUI 装配后仍按比例居中")
    func hostedBySwiftUI() async {
        let size = NSSize(width: 400, height: 400)
        let (host, window) = OffscreenHost.make(
            AnyView(QuickLookPreview(url: movieURL, videoAspect: 16.0 / 9.0)),
            size: size
        )
        defer { window.orderOut(nil) }

        let fitted = await Wait.until {
            host.layoutSubtreeIfNeeded()
            return previewView(in: host)?.frame == NSRect(x: 0, y: 87.5, width: 400, height: 225)
        }

        #expect(fitted)
    }

    // MARK: - 手工搭的宿主

    /// 只用来试摆放：Quick Look 打不开这个路径，但视图与比例判定照常。
    private var movieURL: URL { URL(fileURLWithPath: "/tmp/影片.mov") }

    private func hostView(aspect: CGFloat?) -> QuickLookHostView {
        let host = QuickLookHostView()
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        host.show(url: movieURL, videoAspect: aspect)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func previewView(in view: NSView) -> QLPreviewView? {
        OffscreenHost.allSubviews(of: view).compactMap { $0 as? QLPreviewView }.first
    }
}
