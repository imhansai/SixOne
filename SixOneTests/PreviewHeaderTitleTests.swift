//
//  PreviewHeaderTitleTests.swift
//  SixOneTests
//  预览主标题尽量给出内容身份：文本取首行、颜色取十六进制、无 host 链接取地址。
//

import AppKit
import Testing
@testable import SixOne

@Suite("预览主标题")
@MainActor
struct PreviewHeaderTitleTests {
    private func title(
        _ item: ClipboardItem,
        isEditing: Bool = false,
        fileName: String? = nil,
        linkOrigin: String? = nil
    ) -> String {
        PreviewHeaderTitle.mainTitle(
            for: item,
            isEditing: isEditing,
            fileNameTitle: fileName,
            linkOrigin: linkOrigin
        )
    }

    @Test("文本标题取内容首行，而不是「文本预览」")
    func textUsesContentSnippet() {
        let item = ClipboardItem(kind: .text, text: "  第一行\n第二行  ")
        #expect(title(item) == "第一行 第二行")
    }

    @Test("空文本回落到类别名")
    func emptyTextFallsBackToKindName() {
        let item = ClipboardItem(kind: .text, text: "   \n ")
        #expect(title(item) == Localizer.string("Text"))
    }

    @Test("颜色标题取十六进制色值")
    func colorUsesHexValue() throws {
        let data = try #require(
            PasteboardFormat.colorData(of: NSColor(srgbRed: 0.5, green: 0.25, blue: 0, alpha: 1))
        )
        let item = ClipboardItem(kind: .color, colorData: data)
        #expect(title(item) == "#804000")
    }

    @Test("有 host 的链接取协议与域名，无 host 的链接取地址本身")
    func linkFallsBackToAddress() {
        let web = ClipboardItem(kind: .link, text: "https://example.com/path?q=1")
        #expect(title(web, linkOrigin: "https://example.com") == "https://example.com")

        let mailto = ClipboardItem(kind: .link, text: "mailto:a@example.com")
        #expect(title(mailto) == "mailto:a@example.com")
    }

    @Test("文件优先用真实文件名，没有时用条目标题")
    func filePrefersFileName() {
        let item = ClipboardItem(kind: .file, filePath: "/tmp/a.txt")
        #expect(title(item, fileName: "a.txt") == "a.txt")
        #expect(title(item) == "a.txt")
    }

    @Test("编辑态标题是「编辑」")
    func editingUsesEditTitle() {
        let item = ClipboardItem(kind: .text, text: "内容")
        #expect(title(item, isEditing: true) == Localizer.string("Edit"))
    }
}

@Suite("预览主标题复制按钮")
@MainActor
struct PreviewHeaderCopyActionTests {
    private func copy(
        _ item: ClipboardItem,
        isEditing: Bool = false,
        fileName: String? = nil,
        linkOrigin: String? = nil
    ) -> PreviewHeaderCopy? {
        PreviewHeaderCopyAction.make(
            for: item,
            isEditing: isEditing,
            fileNameTitle: fileName,
            linkOrigin: linkOrigin
        )
    }

    @Test("文本复制完整正文")
    func textCopiesFullText() {
        let item = ClipboardItem(kind: .text, text: "第一行\n第二行")
        let action = copy(item)
        #expect(action?.text == "第一行\n第二行")
        #expect(action?.help == Localizer.string("Copy Text"))
    }

    @Test("颜色复制十六进制色值")
    func colorCopiesHexValue() throws {
        let data = try #require(
            PasteboardFormat.colorData(of: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        )
        let item = ClipboardItem(kind: .color, colorData: data)
        let action = copy(item)
        #expect(action?.text == "#FF0000")
        #expect(action?.help == Localizer.string("Copy Hex Value"))
    }

    @Test("链接优先复制来源，无 host 时复制地址本身")
    func linkCopiesOriginOrAddress() {
        let web = ClipboardItem(kind: .link, text: "https://example.com/path")
        #expect(copy(web, linkOrigin: "https://example.com")?.text == "https://example.com")
        #expect(copy(web, linkOrigin: "https://example.com")?.help == Localizer.string("Copy Origin"))

        let mailto = ClipboardItem(kind: .link, text: "  mailto:a@example.com ")
        #expect(copy(mailto)?.text == "mailto:a@example.com")
        #expect(copy(mailto)?.help == Localizer.string("Copy Link"))
    }

    @Test("文件复制文件名；没有文件名时不出现按钮")
    func fileCopiesFileName() {
        let file = ClipboardItem(kind: .file, filePath: "/tmp/a.txt")
        #expect(copy(file, fileName: "a.txt")?.text == "a.txt")
        #expect(copy(file, fileName: "a.txt")?.help == Localizer.string("Copy File Name"))
        #expect(copy(file)?.text == nil)
    }

    @Test("编辑态不出现复制按钮")
    func editingHidesCopy() {
        let item = ClipboardItem(kind: .text, text: "内容")
        #expect(copy(item, isEditing: true)?.text == nil)
    }
}
