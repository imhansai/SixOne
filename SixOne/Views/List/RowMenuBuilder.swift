//
//  RowMenuBuilder.swift
//  SixOne
//
//  历史列表的行右键菜单：把 `ItemCommand` 的布局渲染成 NSMenu。
//

import AppKit

/// 行菜单的依赖与落点：面板动作、选中、复制反馈与删除收尾。
struct RowMenuBuilder {
    let manager: ClipboardManager
    let panelActions: () -> PanelActionHandler?
    let selectRow: (UUID) -> Void
    let copyFeedback: (UUID) -> Void
    let deleteRow: (UUID) -> Void

    func makeMenu(for row: HistoryRow, anchor: RowInteractionHost.HostView) -> NSMenu {
        selectRow(row.id)

        let items = menuItems(for: row, anchor: anchor)

        // 备用项露面会撑宽菜单导致跳变：先按全部露出量一次宽度，再钉成最小宽度。
        let alternates = items.filter(\.isAlternate)
        alternates.forEach { $0.isAlternate = false }
        let measuring = NSMenu()
        items.forEach(measuring.addItem)
        let minimumWidth = measuring.size.width
        measuring.removeAllItems()
        alternates.forEach { $0.isAlternate = true }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = minimumWidth
        items.forEach(menu.addItem)
        return menu
    }

    /// 顺序、标题、快捷键都在 `ItemCommand` 里，这里只渲染。
    private func menuItems(for row: HistoryRow, anchor: RowInteractionHost.HostView) -> [NSMenuItem] {
        let layout = ItemCommand.rowMenuLayout(for: row.kind)
        let needsReachableFile = layout.contains { entry in
            guard case .command(let command) = entry else { return false }
            return command.requiresReachableFile
        }
        let canOpenExternally = needsReachableFile && manager.canOpenExternally(id: row.id)
        return layout.map { entry in
            switch entry {
            case .separator:
                return .separator()
            case .command(let command):
                return menuItem(
                    for: command,
                    row: row,
                    anchor: anchor,
                    canOpenExternally: canOpenExternally
                )
            }
        }
    }

    /// 渲染一条动作；源文件不在了就把分享/打开置灰。
    private func menuItem(
        for command: ItemCommand,
        row: HistoryRow,
        anchor: RowInteractionHost.HostView,
        canOpenExternally: Bool
    ) -> NSMenuItem {
        let item = menuItem(
            command.title,
            target: anchor,
            keyEquivalent: command.keyEquivalent ?? "",
            modifiers: command.modifiers,
            isAlternate: command.isAlternate,
            handler: { [self] in perform(command, on: row, anchor: anchor) }
        )
        if command.requiresReachableFile {
            item.isEnabled = canOpenExternally
        }
        return item
    }

    private func perform(_ command: ItemCommand, on row: HistoryRow, anchor: RowInteractionHost.HostView) {
        let actions = panelActions()
        switch command {
        case .paste:
            actions?.panelDidActivate(id: row.id)
        case .pasteAsPlainText:
            actions?.panelDidPasteAsPlainText(id: row.id)
        case .copy:
            manager.copy(id: row.id)
            copyFeedback(row.id)
        case .copyAsPlainText:
            manager.copyAsPlainText(id: row.id)
            copyFeedback(row.id)
        case .share:
            actions?.panelDidRequestShare(id: row.id, anchorView: anchor)
        case .open:
            actions?.panelDidRequestOpen(id: row.id)
        case .delete:
            deleteRow(row.id)
        case .preview, .revealInFinder:
            break
        }
    }

    /// 动作挂在 `representedObject` 上，避免 NSMenuItem.target 的弱引用提前释放。
    private func menuItem(
        _ title: String,
        target: RowInteractionHost.HostView,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        isAlternate: Bool = false,
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(RowInteractionHost.HostView.performMenuAction(_:)),
            keyEquivalent: keyEquivalent
        )
        item.target = target
        item.keyEquivalentModifierMask = modifiers
        item.isAlternate = isAlternate
        item.representedObject = MenuAction(handler)
        return item
    }
}
