//
//  PanelCommandAvailabilityTests.swift
//  SixOneTests

import Testing
@testable import SixOne

@Suite("面板菜单命令可用态")
struct PanelCommandAvailabilityTests {
    private func availability(
        selection: ClipboardItemKind? = .text,
        canOpen: Bool = false,
        canReveal: Bool = false,
        previewing: Bool = false,
        editing: Bool = false,
        previewEditing: Bool = false
    ) -> PanelCommandAvailability {
        PanelCommandAvailability(
            isPanelKeyWindow: true,
            isTextEditing: editing || previewEditing,
            hasSelection: selection != nil,
            selectionKind: selection,
            isPreviewing: previewing,
            canOpenExternally: canOpen,
            hasRevealableFile: canReveal,
            hasHistory: true,
            isEditing: previewEditing
        )
    }

    @Test("面板不是 key 窗口：所有命令都不可用")
    func panelNotKey() {
        var value = availability()
        value.isPanelKeyWindow = false
        for command in PanelMenuCommand.allCases {
            #expect(!value.isEnabled(command), "\(command) 不该在非 key 面板里可用")
        }
    }

    @Test("文本编辑中：面板命令一律让路，只有「存储」例外")
    func textEditingDisablesEverything() {
        let value = availability(selection: .text, canOpen: true, editing: true)
        for command in PanelMenuCommand.allCases where command != .saveEditing {
            #expect(!value.isEnabled(command), "\(command) 编辑中不该由面板处理")
        }
        #expect(!value.isEnabled(.saveEditing), "只有搜索框/查找栏编辑时没有可存储的内容")
    }

    @Test("Save：只在预览正文编辑中可用")
    func saveEditing() {
        #expect(!availability(previewEditing: false).isEnabled(.saveEditing))
        #expect(availability(previewEditing: true).isEnabled(.saveEditing))

        var notKey = availability(previewEditing: true)
        notKey.isPanelKeyWindow = false
        #expect(!notKey.isEnabled(.saveEditing), "面板不是 key 时命令不可用")
    }

    @Test("Copy / Paste：有选中或聚焦了组内文件即可用")
    func copyAndPaste() {
        var value = availability(selection: nil)
        #expect(!value.isEnabled(.copy))
        #expect(!value.isEnabled(.paste))

        value = availability(selection: .text)
        #expect(value.isEnabled(.copy))
        #expect(value.isEnabled(.paste))

        value = availability(selection: nil)
        value.focusedGroupFileIndex = 2
        #expect(value.isEnabled(.copy))
        #expect(value.isEnabled(.paste))
    }

    @Test("纯文本拷贝 / 粘贴：只对文本、链接、颜色有意义")
    func plainTextKinds() {
        for kind in [ClipboardItemKind.text, .link, .color] {
            let value = availability(selection: kind)
            #expect(value.isEnabled(.copyAsPlainText), "\(kind) 应有纯文本形态")
            #expect(value.isEnabled(.pasteAsPlainText), "\(kind) 应有纯文本形态")
        }
        for kind in [ClipboardItemKind.image, .file] {
            let value = availability(selection: kind)
            #expect(!value.isEnabled(.copyAsPlainText), "\(kind) 没有纯文本形态")
            #expect(!value.isEnabled(.pasteAsPlainText), "\(kind) 没有纯文本形态")
        }
    }

    @Test("纯文本命令不作用于文件组里聚焦的单个文件")
    func plainTextExcludesFocusedFile() {
        var value = availability(selection: .text)
        value.focusedGroupFileIndex = 0
        #expect(!value.isEnabled(.copyAsPlainText))
        #expect(!value.isEnabled(.pasteAsPlainText))
    }

    @Test("Delete：只作用于整条选中")
    func delete() {
        #expect(availability(selection: .text).isEnabled(.delete))
        #expect(!availability(selection: nil).isEnabled(.delete))
    }

    @Test("Preview：有选中或已开预览时可用；编辑中不可用")
    func preview() {
        #expect(availability(selection: .text).isEnabled(.preview))
        #expect(!availability(selection: nil).isEnabled(.preview))
        #expect(availability(selection: nil, previewing: true).isEnabled(.preview))
        #expect(!availability(selection: .text, previewing: true, editing: true).isEnabled(.preview))
    }

    @Test("Open / Share / Reveal：类型与可达性都要满足")
    func openShareReveal() {
        let file = availability(selection: .file, canOpen: true, canReveal: true)
        #expect(file.isEnabled(.open))
        #expect(file.isEnabled(.share))
        #expect(file.isEnabled(.reveal))

        let image = availability(selection: .image, canOpen: true, canReveal: true)
        #expect(image.isEnabled(.open))
        #expect(image.isEnabled(.share))
        #expect(image.isEnabled(.reveal))

        let inlineImage = availability(selection: .image, canOpen: true, canReveal: false)
        #expect(inlineImage.isEnabled(.open))
        #expect(!inlineImage.isEnabled(.reveal))

        let link = availability(selection: .link, canOpen: true)
        #expect(link.isEnabled(.open))
        #expect(link.isEnabled(.share))
        #expect(!link.isEnabled(.reveal), "链接没有可揭示的本地文件")

        let text = availability(selection: .text, canOpen: false)
        #expect(!text.isEnabled(.open))
        #expect(!text.isEnabled(.share))
        #expect(!text.isEnabled(.reveal))

        let unavailableFile = availability(selection: .file, canOpen: false)
        #expect(!unavailableFile.isEnabled(.open))
        #expect(!unavailableFile.isEnabled(.share))
    }

    @Test("Clear History：历史非空才可用")
    func clearHistory() {
        var value = availability()
        #expect(value.isEnabled(.clearHistory))
        value.hasHistory = false
        #expect(!value.isEnabled(.clearHistory))
    }

    @Test("Search：预览中或编辑中不可用")
    func focusSearch() {
        #expect(availability().isEnabled(.focusSearch))
        #expect(!availability(previewing: true).isEnabled(.focusSearch))
        #expect(!availability(editing: true).isEnabled(.focusSearch))
    }
}
