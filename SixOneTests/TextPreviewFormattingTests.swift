//
//  TextPreviewFormattingTests.swift
//  SixOneTests
//  文本预览默认纯文本，开「显示格式」或进编辑态才装回原始 RTF。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("文本预览的富文本展示")
@MainActor
struct TextPreviewFormattingTests {
    private static let plainPointSize: CGFloat = 14
    private static let richPointSize: CGFloat = 30

    @Test("富文本条目只读预览默认按纯文本展示")
    func defaultsToPlainText() async throws {
        let (context, item) = try makeRichItem()
        let (hosting, window) = makeHost(context, item: item)
        defer { window.orderOut(nil) }

        let textView = try await bodyTextView(in: hosting)
        #expect(textView.string == "Hello World")
        #expect(pointSize(of: textView) == Self.plainPointSize, "默认应当压掉格式，显示纯文本")
    }

    @Test("打开「显示格式」后按原始富文本展示，再关掉回到纯文本")
    func togglingFormattingSwitchesDisplay() async throws {
        let (context, item) = try makeRichItem()
        let (hosting, window) = makeHost(context, item: item)
        defer { window.orderOut(nil) }

        let textView = try await bodyTextView(in: hosting)
        #expect(pointSize(of: textView) == Self.plainPointSize)

        context.previewState.showsFormatting = true
        #expect(await Wait.until { pointSize(of: textView) == Self.richPointSize }, "开关打开后应显示原始富文本")

        context.previewState.showsFormatting = false
        #expect(await Wait.until { pointSize(of: textView) == Self.plainPointSize }, "开关关掉后应回到纯文本")
    }

    @Test("进入编辑一律装回原始富文本")
    func editingAlwaysShowsRichText() async throws {
        let (context, item) = try makeRichItem()
        let (hosting, window) = makeHost(context, item: item)
        defer { window.orderOut(nil) }

        let textView = try await bodyTextView(in: hosting)
        #expect(pointSize(of: textView) == Self.plainPointSize)

        context.previewState.startEditing()
        #expect(await Wait.until { textView.isEditable }, "进入编辑后正文应当可编辑")
        #expect(await Wait.until { pointSize(of: textView) == Self.richPointSize }, "编辑态应当装回原始富文本")

        context.previewState.finishEditing()
        #expect(await Wait.until { pointSize(of: textView) == Self.plainPointSize }, "退出编辑后应回到纯文本")
    }

    @Test("纯文本预览下编辑保存，不会丢掉原始格式")
    func editingFromPlainPreservesFormatting() async throws {
        let (context, item) = try makeRichItem()
        let (hosting, window) = makeHost(context, item: item)
        defer { window.orderOut(nil) }

        let textView = try await bodyTextView(in: hosting)
        context.previewState.startEditing()
        #expect(await Wait.until { textView.isEditable && pointSize(of: textView) == Self.richPointSize })

        textView.textStorage?.append(
            NSAttributedString(
                string: " tail",
                attributes: [.font: NSFont.systemFont(ofSize: Self.richPointSize)]
            )
        )
        context.previewState.finishEditing()

        #expect(await Wait.until { item.text == "Hello World tail" }, "编辑结果应当落回条目")
        let saved = try #require(item.attributedTextData, "带格式的编辑结果不应被压成纯文本")
        let decoded = try #require(NSAttributedString(rtf: saved, documentAttributes: nil))
        #expect(decoded.string == "Hello World tail")
        #expect(pointSize(of: decoded) == Self.richPointSize, "保存的 RTF 应当保留原始字号")

        #expect(await Wait.until { pointSize(of: textView) == Self.plainPointSize }, "退出编辑后预览应回到纯文本")
    }

    @Test("⌘S 保存后仍留在编辑态")
    func saveKeepsEditing() async throws {
        let (context, item) = try makeRichItem()
        let (hosting, window) = makeHost(context, item: item)
        defer { window.orderOut(nil) }

        let textView = try await bodyTextView(in: hosting)
        context.previewState.startEditing()
        #expect(await Wait.until { textView.isEditable && pointSize(of: textView) == Self.richPointSize })

        textView.textStorage?.append(
            NSAttributedString(
                string: " tail",
                attributes: [.font: NSFont.systemFont(ofSize: Self.richPointSize)]
            )
        )
        #expect(await Wait.until { context.previewState.hasUnsavedChanges })

        context.previewState.requestSave()

        #expect(await Wait.until { item.text == "Hello World tail" }, "保存应落回条目")
        #expect(textView.isEditable, "⌘S 不应退出编辑")
        #expect(context.previewState.isEditing)
        #expect(!context.previewState.hasUnsavedChanges, "保存后改动标记应清掉")
    }

    @Test("取消编辑：正文恢复进入编辑前的内容，条目不被改写")
    func cancelEditingRestoresBaseline() async throws {
        let (context, item) = try makeRichItem()
        let (hosting, window) = makeHost(context, item: item)
        defer { window.orderOut(nil) }

        let textView = try await bodyTextView(in: hosting)
        context.previewState.startEditing()
        #expect(await Wait.until { textView.isEditable && pointSize(of: textView) == Self.richPointSize })

        textView.textStorage?.append(
            NSAttributedString(
                string: " tail",
                attributes: [.font: NSFont.systemFont(ofSize: Self.richPointSize)]
            )
        )
        #expect(await Wait.until { context.previewState.hasUnsavedChanges }, "编辑后应标记有改动")
        context.previewState.cancelEditing()
        #expect(!context.previewState.hasUnsavedChanges, "取消后应清掉改动标记")

        #expect(await Wait.until { !textView.isEditable }, "取消后应退回只读")
        #expect(await Wait.until { textView.string == "Hello World" }, "正文应恢复进入编辑前的快照")
        #expect(await Wait.until { pointSize(of: textView) == Self.plainPointSize }, "只读态回到纯文本显示")
        #expect(item.text == "Hello World", "取消编辑不能改写条目")

        let saved = try #require(item.attributedTextData, "原始富文本不应被取消操作冲掉")
        let decoded = try #require(NSAttributedString(rtf: saved, documentAttributes: nil))
        #expect(decoded.string == "Hello World")
    }

    @Test("关闭预览会复位显示格式开关")
    func closeResetsFormattingToggle() {
        let state = PreviewState()
        state.showsFormatting = true
        state.close()
        #expect(!state.showsFormatting, "关掉预览后应回到「默认纯文本」")
    }
}

// MARK: - 夹具

@MainActor
private func makeRichItem() throws -> (PanelContext, ClipboardItem) {
    let harness = try ClipboardHarness()
    let context = PanelContext(
        manager: harness.manager,
        store: HistoryListStore(repository: FakeHistoryRepository(), events: ClipboardHistoryEventBus()),
        caches: PanelCaches()
    )
    let rtf = try richText("Hello World")
    let item = ClipboardItem(kind: .text, text: "Hello World", attributedTextData: rtf)
    // 编辑保存按 id 取整条，条目必须在库里。
    harness.context.insert(item)
    try harness.context.save()
    context.previewState.item = item
    return (context, item)
}

private func richText(_ string: String) throws -> Data {
    let attributed = NSAttributedString(
        string: string,
        attributes: [
            .font: NSFont.systemFont(ofSize: 30),
            .foregroundColor: NSColor.systemRed,
        ]
    )
    return try attributed.data(
        from: NSRange(location: 0, length: attributed.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
}

@MainActor
private func makeHost(_ context: PanelContext, item: ClipboardItem) -> (NSHostingView<AnyView>, NSWindow) {
    let size = NSSize(width: ClipboardLayout.panelWidth, height: ClipboardLayout.panelHeight)
    return OffscreenHost.make(
        AnyView(
            PreviewDetailView(item: item)
                .frame(width: size.width, height: size.height)
                .environment(context)
        ),
        size: size
    )
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

@MainActor
private func pointSize(of textView: NSTextView) -> CGFloat? {
    guard let storage = textView.textStorage, storage.length > 0 else { return nil }
    return pointSize(of: storage)
}

@MainActor
private func pointSize(of attributed: NSAttributedString) -> CGFloat? {
    guard attributed.length > 0 else { return nil }
    return (attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
}
