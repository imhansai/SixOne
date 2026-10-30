//
//  RowMenuBuilderTests.swift
//  SixOneTests

import AppKit
import Foundation
import Testing
@testable import SixOne

@Suite("行右键菜单")
@MainActor
struct RowMenuBuilderTests {
    @Test("拷贝：真的写回剪贴板，并给出复制反馈")
    func copyWritesBackToPasteboard() throws {
        let harness = try ClipboardHarness()
        let rtf = Data("{\\rtf1\\ansi 菜单}".utf8)
        let item = try insert(ClipboardItem(kind: .text, text: "菜单拷贝", attributedTextData: rtf), into: harness)
        var feedback: [UUID] = []

        let menu = makeMenu(for: item, harness: harness, onCopyFeedback: { feedback.append($0) })
        try run(ItemCommand.copy, in: menu)

        #expect(harness.pasteboard.lastWrite == .text("菜单拷贝", rtf: rtf))
        #expect(feedback == [item.id])
    }

    @Test("拷贝为纯文本：只写文字，不带富文本")
    func copyAsPlainTextWritesTextOnly() throws {
        let harness = try ClipboardHarness()
        let rtf = Data("{\\rtf1\\ansi 菜单}".utf8)
        let item = try insert(ClipboardItem(kind: .text, text: "菜单拷贝", attributedTextData: rtf), into: harness)
        var feedback: [UUID] = []

        let menu = makeMenu(for: item, harness: harness, onCopyFeedback: { feedback.append($0) })
        try run(ItemCommand.copyAsPlainText, in: menu)

        #expect(harness.pasteboard.lastWrite == .text("菜单拷贝", rtf: nil))
        #expect(feedback == [item.id])
    }

    @Test("删除：交给列表收尾（库与选中态）")
    func deleteGoesToTheList() throws {
        let harness = try ClipboardHarness()
        let item = try insert(ClipboardItem(kind: .text, text: "待删"), into: harness)
        var deleted: [UUID] = []
        let builder = RowMenuBuilder(
            manager: harness.manager,
            panelActions: { nil },
            selectRow: { _ in },
            copyFeedback: { _ in },
            copyItem: { harness.manager.copy(id: $0) },
            copyItemAsPlainText: { harness.manager.copyAsPlainText(id: $0) },
            deleteRow: { deleted.append($0) }
        )

        let menu = builder.makeMenu(for: HistoryRow(item), anchor: RowInteractionHost.HostView())
        try run(ItemCommand.delete, in: menu)

        #expect(deleted == [item.id])
    }

    @Test("源文件还在：分享与打开可用；文件没了：两项一起置灰")
    func reachableFileGatesShareAndOpen() throws {
        let harness = try ClipboardHarness()
        let file = try TemporaryFiles.makeFile(prefix: "sixone-menu", contents: "x")
        defer { try? FileManager.default.removeItem(at: file) }
        let item = try insert(ClipboardItem(kind: .file, filePath: file.path), into: harness)
        let builder = RowMenuBuilder(
            manager: harness.manager,
            panelActions: { nil },
            selectRow: { _ in },
            copyFeedback: { _ in },
            copyItem: { harness.manager.copy(id: $0) },
            copyItemAsPlainText: { harness.manager.copyAsPlainText(id: $0) },
            deleteRow: { _ in }
        )
        let anchor = RowInteractionHost.HostView()

        let enabledMenu = builder.makeMenu(for: HistoryRow(item), anchor: anchor)
        #expect(try menuItem(ItemCommand.share, in: enabledMenu).isEnabled)
        #expect(try menuItem(ItemCommand.open, in: enabledMenu).isEnabled)

        try FileManager.default.removeItem(at: file)

        let disabledMenu = builder.makeMenu(for: HistoryRow(item), anchor: anchor)
        #expect(try !menuItem(ItemCommand.share, in: disabledMenu).isEnabled)
        #expect(try !menuItem(ItemCommand.open, in: disabledMenu).isEnabled)
    }

    // MARK: - 夹具

    private func makeMenu(
        for item: ClipboardItem,
        harness: ClipboardHarness,
        onCopyFeedback: @escaping (UUID) -> Void
    ) -> NSMenu {
        let builder = RowMenuBuilder(
            manager: harness.manager,
            panelActions: { nil },
            selectRow: { _ in },
            copyFeedback: onCopyFeedback,
            copyItem: { harness.manager.copy(id: $0) },
            copyItemAsPlainText: { harness.manager.copyAsPlainText(id: $0) },
            deleteRow: { _ in }
        )
        return builder.makeMenu(for: HistoryRow(item), anchor: RowInteractionHost.HostView())
    }

    private func run(_ command: ItemCommand, in menu: NSMenu) throws {
        (try menuItem(command, in: menu).representedObject as? MenuAction)?.run()
    }

    private func menuItem(_ command: ItemCommand, in menu: NSMenu) throws -> NSMenuItem {
        try #require(menu.items.first { $0.title == command.title }, "菜单里没有「\(command.title)」")
    }

    @discardableResult
    private func insert(_ item: ClipboardItem, into harness: ClipboardHarness) throws -> ClipboardItem {
        harness.context.insert(item)
        try harness.context.save()
        return item
    }
}
