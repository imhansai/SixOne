//
//  FilePathBarTests.swift
//  SixOneTests
//  预览路径行：长路径横向滚动、短路径铺满、文本可选择、无选区 ⌘C 复制整段。
//

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("预览路径行")
@MainActor
struct FilePathBarTests {
    @Test("长路径可横向滚动")
    func longPathScrollsHorizontally() async throws {
        let location = try #require(FileLocation(
            path: "/Users/example/" + String(repeating: "very-long-folder/", count: 20) + "a.kt"
        ))
        let size = NSSize(width: 400, height: ClipboardLayout.pathBarHeight)
        let (hosting, window) = Self.makeHost(location: location, size: size)
        defer { window.orderOut(nil) }

        let textView = try #require(await Self.pathTextView(in: hosting))
        let scrollView = try #require(textView.enclosingScrollView)

        #expect(textView.isSelectable)
        #expect(!textView.isEditable)
        #expect(
            (scrollView.documentView?.frame.width ?? 0) > scrollView.contentSize.width + 1,
            "长路径应当有横向滚动空间"
        )

        scrollView.contentView.scroll(to: NSPoint(x: 40, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        #expect(scrollView.documentVisibleRect.origin.x > 0, "长路径应能横向滚动")
    }

    @Test("短路径铺满可视区，不留滚动空间")
    func shortPathFillsVisibleWidth() async throws {
        let location = try #require(FileLocation(path: "/tmp/a.txt"))
        let size = NSSize(width: 400, height: ClipboardLayout.pathBarHeight)
        let (hosting, window) = Self.makeHost(location: location, size: size)
        defer { window.orderOut(nil) }

        let textView = try #require(await Self.pathTextView(in: hosting))
        let scrollView = try #require(textView.enclosingScrollView)

        #expect(
            abs((scrollView.documentView?.frame.width ?? 0) - scrollView.contentSize.width) <= 1,
            "短路径不该产生滚动"
        )
    }

    @Test("无选区时 ⌘C 复制整段路径")
    func copyWithoutSelectionCopiesWholePath() {
        let textView = Self.makeTextView(path: "/Users/example/a.txt")
        var copied: String?
        textView.onCopyWhole = { copied = textView.string }

        textView.copy(nil)

        #expect(copied == "/Users/example/a.txt")
    }

    @Test("菜单校验：无选区的 Copy 仍然可用，整段复制才有入口")
    func validatesCopyWithoutSelection() {
        let textView = Self.makeTextView(path: "/tmp/a.txt")
        textView.onCopyWhole = {}
        let item = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")

        #expect(textView.validateUserInterfaceItem(item))
    }

        // MARK: - 预览接入

    @Test("单文件预览显示源文件路径")
    func previewShowsPathForSingleFile() async throws {
        let path = try Self.makeTemporaryFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let item = ClipboardItem(kind: .file, filePaths: [path])

        let (hosting, window) = try Self.makePreviewHost(item: item)
        defer { window.orderOut(nil) }

        let textView = try #require(await Self.pathTextView(in: hosting))
        #expect(textView.string == path)
    }

    @Test("磁盘图片预览显示源文件路径")
    func previewShowsPathForImageFile() async throws {
        let path = try Self.makeTemporaryFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let item = ClipboardItem(
            kind: .image,
            imageData: Data([0x00]),
            filePaths: [path],
            contentType: "PNG"
        )

        let (hosting, window) = try Self.makePreviewHost(item: item)
        defer { window.orderOut(nil) }

        let textView = try #require(await Self.pathTextView(in: hosting))
        #expect(textView.string == path)
    }

    @Test("文件组进入某一项时显示该项当前路径")
    func previewShowsPathForGroupItem() async throws {
        let path = try Self.makeTemporaryFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let context = try TestPanel.context()
        context.previewState.scopedGroupURLs = [
            ScopedFileURL(url: URL(fileURLWithPath: path), needsStop: false),
            nil,
        ]
        context.previewState.showGroupFile(0)
        let item = ClipboardItem(kind: .file, filePaths: [path, path + ".missing"])

        let (hosting, window) = try Self.makePreviewHost(item: item, context: context)
        defer { window.orderOut(nil) }

        let textView = try #require(await Self.pathTextView(in: hosting))
        #expect(textView.string == path)
    }

    @Test("纯文本条目不显示路径")
    func previewHidesPathForText() async throws {
        let item = ClipboardItem(kind: .text, text: "hello")
        let (hosting, window) = try Self.makePreviewHost(item: item)
        defer { window.orderOut(nil) }

        await Wait.settle(milliseconds: 200)
        #expect(Self.findPathTextView(in: hosting) == nil)
    }

    @Test("无源文件的位图不显示路径")
    func previewHidesPathForBitmapOnly() async throws {
        let item = ClipboardItem(kind: .image, imageData: Data([0x00]), contentType: "PNG")
        let (hosting, window) = try Self.makePreviewHost(item: item)
        defer { window.orderOut(nil) }

        await Wait.settle(milliseconds: 200)
        #expect(Self.findPathTextView(in: hosting) == nil)
    }

    @Test("文件组总览不显示路径")
    func previewHidesPathInGroupOverview() async throws {
        let item = ClipboardItem(kind: .file, filePaths: ["/tmp/a.txt", "/tmp/b.txt"])
        let (hosting, window) = try Self.makePreviewHost(item: item)
        defer { window.orderOut(nil) }

        await Wait.settle(milliseconds: 200)
        #expect(Self.findPathTextView(in: hosting) == nil)
    }

    // MARK: - 工具

    private static func makeHost(
        location: FileLocation,
        size: NSSize
    ) -> (host: NSHostingView<AnyView>, window: NSWindow) {
        OffscreenHost.make(
            AnyView(
                FilePathBar(location: location, onCopy: { _ in }, onPaste: {})
                    .frame(width: size.width, height: size.height)
            ),
            size: size
        )
    }

    private static func makePreviewHost(
        item: ClipboardItem,
        context: PanelContext? = nil
    ) throws -> (host: NSHostingView<AnyView>, window: NSWindow) {
        let context = try context ?? TestPanel.context()
        let size = ClipboardLayout.panelSize
        let hosting = NSHostingView(rootView: AnyView(
            PreviewDetailView(item: item)
                .frame(width: size.width, height: size.height)
                .environment(context)
        ))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    private static func makeTemporaryFile() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixone-path-\(UUID().uuidString).txt")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private static func makeTextView(path: String) -> SelectablePathTextView {
        let textView = SelectablePathTextView(frame: NSRect(x: 0, y: 0, width: 320, height: ClipboardLayout.pathBarHeight))
        textView.string = path
        textView.isEditable = false
        textView.isSelectable = true
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return textView
    }

    private static func pathTextView(in host: NSView) async -> SelectablePathTextView? {
        let appeared = await Wait.until {
            findPathTextView(in: host) != nil
        }
        // 多等一拍，让滚动视图完成首次布局。
        await Wait.settle(milliseconds: 100)
        return appeared ? findPathTextView(in: host) : nil
    }

    private static func findPathTextView(in view: NSView) -> SelectablePathTextView? {
        if let textView = view as? SelectablePathTextView { return textView }
        for subview in view.subviews {
            if let found = findPathTextView(in: subview) { return found }
        }
        return nil
    }
}
