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
            fileCapabilities: makeCache(),
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

    @Test("别名菜单标题随是否已设置切换")
    func aliasMenuTitleFollowsState() throws {
        let harness = try ClipboardHarness()
        let item = try insert(ClipboardItem(kind: .text, text: "x"), into: harness)
        let builder = RowMenuBuilder(
            manager: harness.manager,
            fileCapabilities: makeCache(),
            panelActions: { nil },
            selectRow: { _ in },
            copyFeedback: { _ in },
            copyItem: { _ in },
            copyItemAsPlainText: { _ in },
            deleteRow: { _ in }
        )
        let anchor = RowInteractionHost.HostView()

        let addMenu = builder.makeMenu(for: HistoryRow(item), anchor: anchor)
        #expect(addMenu.items.contains { $0.title == Localizer.string("Add Alias…") })

        item.alias = "别名"
        let editMenu = builder.makeMenu(for: HistoryRow(item), anchor: anchor)
        #expect(editMenu.items.contains { $0.title == Localizer.string("Edit Alias…") })
    }

    @Test("移到分组子菜单：未分组、各分组与新建分组，当前归属打勾")
    func moveToGroupSubmenu() throws {
        let harness = try ClipboardHarness()
        let group = CollectionRow(id: UUID(), name: "Work", createdAt: Date())
        let item = try insert(
            ClipboardItem(kind: .text, text: "x", collectionID: group.id),
            into: harness
        )
        let builder = RowMenuBuilder(
            manager: harness.manager,
            fileCapabilities: makeCache(),
            panelActions: { nil },
            selectRow: { _ in },
            copyFeedback: { _ in },
            copyItem: { _ in },
            copyItemAsPlainText: { _ in },
            deleteRow: { _ in },
            collections: { [group] }
        )

        let menu = builder.makeMenu(
            for: HistoryRow(item),
            anchor: RowInteractionHost.HostView()
        )
        let move = try #require(
            menu.items.first { $0.title == ItemCommand.moveToGroup.title }
        )
        let submenu = try #require(move.submenu)

        #expect(
            submenu.items.first { $0.title == Localizer.string("Ungrouped") }?.state
                == .off
        )
        #expect(submenu.items.first { $0.title == group.name }?.state == .on)
        #expect(submenu.items.contains { $0.title == Localizer.string("New Group…") })
    }

    @Test("移到分组子菜单动作落到面板归属接口")
    func moveToGroupActionWiresToPanel() throws {
        let harness = try ClipboardHarness()
        let group = CollectionRow(id: UUID(), name: "Work", createdAt: Date())
        let item = try insert(ClipboardItem(kind: .text, text: "x"), into: harness)
        let spy = SpyItemActions()
        let builder = RowMenuBuilder(
            manager: harness.manager,
            fileCapabilities: makeCache(),
            panelActions: { spy },
            selectRow: { _ in },
            copyFeedback: { _ in },
            copyItem: { _ in },
            copyItemAsPlainText: { _ in },
            deleteRow: { _ in },
            collections: { [group] }
        )

        let menu = builder.makeMenu(
            for: HistoryRow(item),
            anchor: RowInteractionHost.HostView()
        )
        let move = try #require(
            menu.items.first { $0.title == ItemCommand.moveToGroup.title }
        )
        let submenu = try #require(move.submenu)

        let groupItem = try #require(submenu.items.first { $0.title == group.name })
        (groupItem.representedObject as? MenuAction)?.run()
        #expect(spy.assignedItemID == item.id)
        #expect(spy.assignedCollectionID == group.id)

        let newGroup = try #require(
            submenu.items.first { $0.title == Localizer.string("New Group…") }
        )
        (newGroup.representedObject as? MenuAction)?.run()
        #expect(spy.newGroupItemID == item.id)
    }

    @Test("搜索态可定位时出现「在历史记录中显示」，动作落到面板")
    func showInHistoryAppearsAndWiresToPanel() throws {
        let harness = try ClipboardHarness()
        let item = try insert(ClipboardItem(kind: .text, text: "定位"), into: harness)
        let spy = SpyItemActions()
        var locatable = true
        let builder = RowMenuBuilder(
            manager: harness.manager,
            fileCapabilities: makeCache(),
            panelActions: { spy },
            selectRow: { _ in },
            copyFeedback: { _ in },
            copyItem: { _ in },
            copyItemAsPlainText: { _ in },
            deleteRow: { _ in },
            canLocateInHistory: { _ in locatable }
        )
        let anchor = RowInteractionHost.HostView()

        let menu = builder.makeMenu(for: HistoryRow(item), anchor: anchor)
        #expect(try menuItem(ItemCommand.showInHistory, in: menu).keyEquivalent == "g")
        try run(ItemCommand.showInHistory, in: menu)
        #expect(spy.locatedItemID == item.id)

        locatable = false
        let hiddenMenu = builder.makeMenu(for: HistoryRow(item), anchor: anchor)
        #expect(!hiddenMenu.items.contains { $0.title == ItemCommand.showInHistory.title })
    }

    @Test("源文件还在：分享与打开可用；文件没了：探测落定后置灰")
    func reachableFileGatesShareAndOpen() async throws {
        let harness = try ClipboardHarness()
        let file = try TemporaryFiles.makeFile(prefix: "sixone-menu", contents: "x")
        defer { try? FileManager.default.removeItem(at: file) }
        let item = try insert(ClipboardItem(kind: .file, filePath: file.path), into: harness)
        let cache = makeCache()
        let builder = RowMenuBuilder(
            manager: harness.manager,
            fileCapabilities: cache,
            panelActions: { nil },
            selectRow: { _ in },
            copyFeedback: { _ in },
            copyItem: { harness.manager.copy(id: $0) },
            copyItemAsPlainText: { harness.manager.copyAsPlainText(id: $0) },
            deleteRow: { _ in }
        )
        let anchor = RowInteractionHost.HostView()

        // 首轮菜单先乐观放行，后台探测落定后仍可用。
        let optimisticMenu = builder.makeMenu(for: HistoryRow(item), anchor: anchor)
        #expect(try menuItem(ItemCommand.share, in: optimisticMenu).isEnabled)
        #expect(await Wait.until { cache.cachedCapabilities(for: item.id)?.canOpen == true })

        let enabledMenu = builder.makeMenu(for: HistoryRow(item), anchor: anchor)
        #expect(try menuItem(ItemCommand.share, in: enabledMenu).isEnabled)
        #expect(try menuItem(ItemCommand.open, in: enabledMenu).isEnabled)

        try FileManager.default.removeItem(at: file)
        cache.invalidateAll()
        // 触发一次重新探测，再等结果落定。
        _ = builder.makeMenu(for: HistoryRow(item), anchor: anchor)
        #expect(await Wait.until { cache.cachedCapabilities(for: item.id)?.canOpen == false })

        let disabledMenu = builder.makeMenu(for: HistoryRow(item), anchor: anchor)
        #expect(try !menuItem(ItemCommand.share, in: disabledMenu).isEnabled)
        #expect(try !menuItem(ItemCommand.open, in: disabledMenu).isEnabled)
    }

    // MARK: - 夹具

    private func makeCache() -> PanelFileCapabilityCache {
        PanelFileCapabilityCache(notificationCenter: nil)
    }

    private func makeMenu(
        for item: ClipboardItem,
        harness: ClipboardHarness,
        onCopyFeedback: @escaping (UUID) -> Void
    ) -> NSMenu {
        let builder = RowMenuBuilder(
            manager: harness.manager,
            fileCapabilities: makeCache(),
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

    @MainActor
    private final class SpyItemActions: ItemActionHandling {
        var assignedItemID: UUID?
        var assignedCollectionID: UUID?
        var newGroupItemID: UUID?
        var locatedItemID: UUID?

        func panelDidActivate(id: UUID, asPlainText: Bool) {}
        func panelDidPasteAsPlainText(id: UUID) {}
        func panelDidRequestDelete(id: UUID) {}
        func panelDidRequestOpen(id: UUID) {}
        func panelDidRequestReveal(id: UUID) {}
        func panelDidRequestOpenInShottr(id: UUID) {}
        func panelDidRequestShare(id: UUID, anchorView: NSView) {}
        func panelDidRequestCopy(id: UUID) {}
        func panelDidRequestCopyAsPlainText(id: UUID) {}
        func panelDidRequestCopyText(_ text: String) {}
        func panelDidRequestThumbnailRefresh(id: UUID) {}
        func panelDidRequestEditAlias(id: UUID, currentAlias: String?) {}

        func panelDidRequestAssignCollection(itemID: UUID, collectionID: UUID?) {
            assignedItemID = itemID
            assignedCollectionID = collectionID
        }

        func panelDidRequestNewCollection(assigningItemID: UUID) {
            newGroupItemID = assigningItemID
        }

        func panelDidRequestShowInHistory(id: UUID) {
            locatedItemID = id
        }
    }
}
