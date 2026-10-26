//
//  FilePathBarTests.swift
//  SixOneTests
//  路径条内容超出宽度时可横向滚动。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("路径条")
@MainActor
struct FilePathBarTests {
    @Test("长路径可横向滚动")
    func scrollsHorizontally() async throws {
        let location = try #require(FileLocation(
            path: "/Users/example/" + String(repeating: "very-long-folder/", count: 20) + "a.kt"
        ))
        let size = NSSize(width: 400, height: ClipboardLayout.pathBarHeight)
        let (hosting, window) = OffscreenHost.make(
            AnyView(
                FilePathBar(location: location) { _ in }
                    .frame(width: size.width, height: size.height)
            ),
            size: size
        )
        defer { window.orderOut(nil) }

        let mounted = await Wait.until { Self.pathScrollView(in: hosting) != nil }
        let scrollView = try #require(
            mounted ? Self.pathScrollView(in: hosting) : nil,
            "没找到路径滚动视图"
        )
        // 不检查内部滚动条：SwiftUI 可能为隐藏的滚动条保留空间，宿主不同表现也不同。
        #expect(
            (scrollView.documentView?.frame.width ?? 0) > scrollView.contentSize.width + 1,
            "长路径应当有横向滚动空间"
        )

        scrollView.contentView.scroll(to: NSPoint(x: 40, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        #expect(scrollView.documentVisibleRect.origin.x > 0, "长路径应能横向滚动")
    }

    private static func pathScrollView(in view: NSView) -> NSScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView,
               scrollView.contentSize.height <= ClipboardLayout.pathBarHeight + 2,
               (scrollView.documentView?.frame.width ?? 0) > scrollView.contentSize.width + 1 {
                return scrollView
            }
            if let found = pathScrollView(in: subview) { return found }
        }
        return nil
    }
}
