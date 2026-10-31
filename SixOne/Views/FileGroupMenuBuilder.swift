//
//  FileGroupMenuBuilder.swift
//  SixOne
//  组内一行的右键菜单：标题与顺序来自 ItemCommand，动作由行视图注入。
//

import AppKit

enum FileGroupMenuBuilder {
    static func makeMenu(
        target: RowInteractionHost.HostView,
        isReachable: Bool,
        onPreview: @escaping () -> Void,
        onPaste: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onShare: @escaping (NSView) -> Void,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item(ItemCommand.preview.title, enabled: isReachable, target: target, handler: onPreview))
        menu.addItem(item(ItemCommand.paste.title, enabled: isReachable, target: target, handler: onPaste))
        menu.addItem(item(ItemCommand.copy.title, enabled: isReachable, target: target, handler: onCopy))
        menu.addItem(.separator())
        menu.addItem(item(ItemCommand.share.title, enabled: isReachable, target: target) {
            onShare(target)
        })
        menu.addItem(item(ItemCommand.open.title, enabled: isReachable, target: target, handler: onOpen))
        menu.addItem(item(ItemCommand.revealInFinder.title, enabled: isReachable, target: target, handler: onReveal))
        return menu
    }

    private static func item(
        _ title: String,
        enabled: Bool,
        target: RowInteractionHost.HostView,
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(RowInteractionHost.HostView.performMenuAction(_:)),
            keyEquivalent: ""
        )
        // NSMenuItem.target 是弱引用，闭包挂在 representedObject 上强持有。
        item.target = target
        item.representedObject = MenuAction(handler)
        item.isEnabled = enabled
        return item
    }
}
