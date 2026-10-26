//
//  MenuKeyEquivalentIndex.swift
//  SixOne
//
//  面板 nonactivating 时的命令键 fallback：从主菜单 key equivalent 建索引，重新校验后派发。
//

import AppKit

@MainActor
struct MenuKeyEquivalentIndex {
    /// 命中的菜单项；action/tag 现读。
    final class Command {
        /// 弱引用：菜单项由主菜单持有，索引不延长其生命周期。
        weak var item: NSMenuItem?

        init(item: NSMenuItem) {
            self.item = item
        }

        var action: Selector? { item?.action }
        var tag: Int { item?.tag ?? 0 }

        /// 同 AppKit 分发：解析 target、校验后发送；不能执行已禁用命令。
        func performValidated() -> Bool {
            guard let item, let action = item.action else { return false }
            guard let target = item.target ?? NSApp.target(
                forAction: action,
                to: nil,
                from: item
            ) else {
                return false
            }

            if let validator = target as? NSMenuItemValidation {
                guard validator.validateMenuItem(item) else { return false }
            } else if let validator = target as? NSUserInterfaceValidations {
                guard validator.validateUserInterfaceItem(item) else { return false }
            } else if !item.isEnabled {
                return false
            }

            return NSApp.sendAction(action, to: target, from: item)
        }
    }

    private struct Key: Hashable {
        let character: String
        let modifiers: UInt
    }

    private var commands: [Key: Command] = [:]

    init(menu: NSMenu?) {
        guard let menu else { return }
        collect(menu)
    }

    func command(for event: NSEvent) -> Command? {
        guard event.type == .keyDown,
              event.modifierFlags.contains(.command),
              let characters = event.charactersIgnoringModifiers,
              characters.count == 1 else {
            return nil
        }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return commands[Key(character: characters.lowercased(), modifiers: modifiers.rawValue)]
    }

    private mutating func collect(_ menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                collect(submenu)
                continue
            }
            guard !item.isSeparatorItem,
                  !item.isHidden,
                  !item.keyEquivalent.isEmpty,
                  item.action != nil else {
                continue
            }
            let modifiers = item.keyEquivalentModifierMask
                .intersection([.command, .shift, .option, .control])
            let key = Key(
                character: item.keyEquivalent.lowercased(),
                modifiers: modifiers.rawValue
            )
            // 重复组合保留先出现的一项，避免后项无声覆盖（唯一性由测试守住）。
            if commands[key] == nil {
                commands[key] = Command(item: item)
            }
        }
    }
}
