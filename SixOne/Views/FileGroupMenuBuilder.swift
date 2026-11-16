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
        for entry in ItemCommand.groupFileMenuLayout {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .command(let command):
                guard let handler = handler(
                    for: command,
                    target: target,
                    onPreview: onPreview,
                    onPaste: onPaste,
                    onCopy: onCopy,
                    onShare: onShare,
                    onOpen: onOpen,
                    onReveal: onReveal
                ) else { continue }
                menu.addItem(item(
                    command.title,
                    enabled: isReachable,
                    target: target,
                    handler: handler
                ))
            }
        }
        return menu
    }

    private static func handler(
        for command: ItemCommand,
        target: RowInteractionHost.HostView,
        onPreview: @escaping () -> Void,
        onPaste: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onShare: @escaping (NSView) -> Void,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void
    ) -> (() -> Void)? {
        switch command {
        case .preview: onPreview
        case .paste: onPaste
        case .copy: onCopy
        case .share: { onShare(target) }
        case .open: onOpen
        case .revealInFinder: onReveal
        default: nil
        }
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
