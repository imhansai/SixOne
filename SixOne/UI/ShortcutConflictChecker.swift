//
//  ShortcutConflictChecker.swift
//  SixOne
//
//  录制全局快捷键时预检主菜单冲突；修饰键与系统占用规则由 `HotKeyManager` 判定。
//

import AppKit

struct ShortcutConflictChecker {
    private let menu: MenuKeyEquivalentIndex

    init(menu: NSMenu?) {
        self.menu = MenuKeyEquivalentIndex(menu: menu)
    }

    /// 该组合是否已被主菜单命令占用。
    func conflictsWithMenu(_ event: NSEvent) -> Bool {
        menu.command(for: event) != nil
    }
}
