//
//  ShortcutConflictChecker.swift
//  SixOne
//
//  录制全局快捷键时预检主菜单与面板命令冲突；含设置模式下被隐藏的项。
//

import AppKit

struct ShortcutConflictChecker {
    private let menu: MenuKeyEquivalentIndex

    init(menu: NSMenu?) {
        // 设置模式会收起面板菜单，但全局热键仍会截走它们。
        self.menu = MenuKeyEquivalentIndex(menu: menu, includesHidden: true)
    }

    func conflictsWithMenu(_ event: NSEvent) -> Bool {
        menu.command(for: event) != nil
    }
}
