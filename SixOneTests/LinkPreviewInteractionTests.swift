//
//  LinkPreviewInteractionTests.swift
//  SixOneTests
//  链接预览就地编辑：顶栏编辑态须传到正文并落盘；盯正文而非按钮。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("链接预览的就地编辑")
@MainActor
struct LinkPreviewEditingTests {
    @Test("顶栏进入编辑后，预览正文变成可编辑")
    func linkPreviewBecomesEditable() async throws {
        let harness = try ClipboardHarness()
        let context = makeContext(harness)
        let item = ClipboardItem(kind: .link, text: "https://example.com/a")
        harness.context.insert(item)
        try harness.context.save()
        context.previewState.item = item

        let (hosting, window) = makeHost(context, item: item)
        defer { window.orderOut(nil) }

        let textView = try await bodyTextView(in: hosting)
        #expect(!textView.isEditable, "没进编辑态时正文应当只读")

        context.previewState.startEditing()
        let becameEditable = await Wait.until { textView.isEditable }
        #expect(becameEditable, "顶栏进入编辑后正文应当可编辑")

        context.previewState.finishEditing()
        let becameReadOnly = await Wait.until { !textView.isEditable }
        #expect(becameReadOnly, "退出编辑后正文应当回到只读")
    }

    @Test("编辑后点完成：新正文落盘并写回剪贴板")
    func linkEditCommits() async throws {
        let harness = try ClipboardHarness()
        let context = makeContext(harness)
        let item = ClipboardItem(kind: .link, text: "https://example.com/a")
        harness.context.insert(item)
        try harness.context.save()
        context.previewState.item = item

        let (hosting, window) = makeHost(context, item: item)
        defer { window.orderOut(nil) }

        let textView = try await bodyTextView(in: hosting)
        context.previewState.startEditing()
        try #require(await Wait.until { textView.isEditable }, "进入编辑后正文应当可编辑")

        textView.string = "https://example.com/edited"
        context.previewState.finishEditing()

        let saved = await Wait.until { item.text == "https://example.com/edited" }
        #expect(saved, "编辑结果应当落回条目")
        #expect(harness.pasteboard.lastWrite == .url("https://example.com/edited"))
        #expect(item.attributedTextData == nil, "链接条目不留 RTF")
    }
}

// MARK: - 夹具

@MainActor
private func makeContext(_ harness: ClipboardHarness) -> PanelContext {
    PanelContext(
        manager: harness.manager,
        store: HistoryListStore(repository: FakeHistoryRepository(), events: ClipboardHistoryEventBus()),
        caches: PanelCaches()
    )
}

/// 挂进真窗口；窗口须在屏上，否则收不到鼠标事件。
@MainActor
private func makeHost(_ context: PanelContext, item: ClipboardItem) -> (NSHostingView<AnyView>, NSWindow) {
    let size = NSSize(width: ClipboardLayout.panelWidth, height: ClipboardLayout.panelHeight)
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
    window.orderFrontRegardless()
    hosting.layoutSubtreeIfNeeded()
    return (hosting, window)
}

@MainActor
private func bodyTextView(in hosting: NSView) async throws -> NSTextView {
    let mounted = await Wait.until {
        PreviewSurfaceProbe(contentView: hosting, firstResponder: nil).previewTextView() != nil
    }
    return try #require(
        mounted ? PreviewSurfaceProbe(contentView: hosting, firstResponder: nil).previewTextView() : nil,
        "没找到预览正文视图"
    )
}
