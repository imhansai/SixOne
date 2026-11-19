//
//  CollectionEditorTests.swift
//  SixOneTests
//  分组编辑器装配：空名/重名禁用提交并内联提示，字数指示与合法名提交。
//

import AppKit
import Testing
@testable import SixOne

@Suite("分组编辑器装配")
@MainActor
struct CollectionEditorTests {
    @Test("新建分组：字数指示、空名/重名内联校验与合法提交")
    func createValidatesInline() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
            window.close()
        }

        var saved: String?
        CollectionEditor.present(
            on: window,
            mode: .create,
            existingNames: ["Work"]
        ) { saved = $0 }

        #expect(await Wait.until { window.attachedSheet != nil }, "弹窗没有作为 sheet 挂上")
        let sheet = try #require(window.attachedSheet)
        let content = try #require(sheet.contentView)
        let views = OffscreenHost.allSubviews(of: content)
        let textFields = views.compactMap { $0 as? NSTextField }
        let field = try #require(textFields.first { $0.isEditable })
        let counter = try #require(
            textFields.first { $0.identifier == CollectionEditor.counterIdentifier }
        )
        let create = try #require(
            views.compactMap { $0 as? NSButton }
                .first { $0.title == CollectionEditor.Mode.create.actionTitle }
        )

        #expect(counter.stringValue == expectedCounter(0), "打开时应显示 0 / 40")
        #expect(counter.accessibilityLabel() == Localizer.string("Character Count"))
        #expect(!create.isEnabled, "空名时创建按钮应禁用")

        edit(field, to: "work")
        #expect(counter.stringValue == expectedCounter("work".count), "字数指示器应跟随输入")
        #expect(!create.isEnabled, "重名时创建按钮应禁用")
        #expect(
            textFields.contains {
                $0 !== field && $0.stringValue == Localizer.string("A group with this name already exists.")
            },
            "重名时应显示内联提示"
        )

        // 无效名按 Return：拦下并保持弹窗。
        sheet.makeFirstResponder(field)
        #expect(await Wait.until { field.currentEditor() != nil })
        let editor = try #require(field.currentEditor() as? NSTextView)
        let handled = field.delegate?.control?(
            field,
            textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )
        #expect(handled == true, "无效名的 Return 应被 delegate 拦下")
        #expect(window.attachedSheet != nil, "校验失败时弹窗应保持打开")

        edit(field, to: String(repeating: "a", count: CollectionNameNormalizer.maxLength + 10))
        #expect(
            field.stringValue.count == CollectionNameNormalizer.maxLength,
            "输入长度应在名称上限处截住，而不是保存时静默截断"
        )
        #expect(counter.stringValue == expectedCounter(CollectionNameNormalizer.maxLength))
        #expect(counter.textColor == .systemOrange, "达到上限时计数转橙")

        edit(field, to: "  Home  ")
        #expect(counter.stringValue == expectedCounter("  Home  ".count))
        #expect(counter.textColor == .secondaryLabelColor)
        #expect(create.isEnabled, "合法名应可提交")
        create.performClick(nil)

        #expect(await Wait.until { window.attachedSheet == nil })
        #expect(saved == "Home", "提交的是归一化后的名字")
    }

    private func expectedCounter(_ count: Int) -> String {
        String(
            format: Localizer.string("%lld / %lld"),
            count,
            CollectionNameNormalizer.maxLength
        )
    }

    /// 直接走 delegate，模拟一次编辑后的状态刷新。
    private func edit(_ field: NSTextField, to text: String) {
        field.stringValue = text
        field.delegate?.controlTextDidChange?(
            Notification(name: NSControl.textDidChangeNotification, object: field)
        )
    }
}
