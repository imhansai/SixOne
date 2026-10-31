//
//  PanelMenuCommandTableTests.swift
//  SixOneTests
//  命令表是菜单项、校验与键位 fallback 的共同来源；漏项或写歪在这里报。
//

import AppKit
import Testing
@testable import SixOne

@Suite("面板命令表")
@MainActor
struct PanelMenuCommandTableTests {
    private final class Target: NSObject, AppMenuTarget {
        @objc func openSettingsFromMenu(_ sender: Any?) {}
    }

    private func allItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in
            guard let submenu = item.submenu else { return [item] }
            return allItems(in: submenu)
        }
    }

    @Test("每个命令都有唯一表项，selector 可反查")
    func coversEveryCommandUniquely() {
        let entries = PanelMenuCommandTable.entries

        for command in PanelMenuCommand.allCases {
            #expect(entries.filter { $0.command == command }.count == 1, "\(command) 缺表项或重复")
        }
        for (index, entry) in entries.enumerated() {
            let earlier = entries[..<index]
            #expect(!earlier.contains { $0.selector == entry.selector }, "重复 selector：\(entry.selector)")
            // 无快捷键的命令（预览/分享/清空）允许共用空键位。
            if !entry.key.isEmpty {
                #expect(
                    !earlier.contains { $0.key == entry.key && $0.modifiers == entry.modifiers },
                    "重复键位：\(entry.key)"
                )
            }
            #expect(PanelMenuCommandTable.command(for: entry.selector) == entry.command)
        }
    }

    @Test("表项与主菜单的标题、键位、动作一致")
    func matchesMainMenu() {
        let menu = MainMenuBuilder.makeMainMenu(target: Target())
        let items = allItems(in: menu)

        for entry in PanelMenuCommandTable.entries {
            let item = items.first { $0.action == entry.selector && !$0.isSeparatorItem }
            #expect(item?.title == entry.title, "\(entry.command) 标题不一致")
            #expect(item?.keyEquivalent == entry.key, "\(entry.command) 键位不一致")
            #expect(item?.keyEquivalentModifierMask == entry.modifiers, "\(entry.command) 修饰键不一致")
        }
    }
}
