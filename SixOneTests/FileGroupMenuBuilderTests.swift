//
//  FileGroupMenuBuilderTests.swift
//  SixOneTests
//  组内行菜单：顺序、启用状态与动作路由。
//

import AppKit
import Testing
@testable import SixOne

@Suite("文件组行菜单")
@MainActor
struct FileGroupMenuBuilderTests {
    @Test("菜单顺序跟随 ItemCommand，可达性控制启用，动作各自回传")
    func buildsMenuAndRoutesActions() {
        let host = RowInteractionHost.HostView()
        var calls: [String] = []
        let menu = FileGroupMenuBuilder.makeMenu(
            target: host,
            isReachable: true,
            onPreview: { calls.append("preview") },
            onPaste: { calls.append("paste") },
            onCopy: { calls.append("copy") },
            onShare: { _ in calls.append("share") },
            onOpen: { calls.append("open") },
            onReveal: { calls.append("reveal") }
        )

        #expect(menu.items.count == 7)
        #expect(menu.items[3].isSeparatorItem)
        #expect(menu.items.map(\.title) == [
            ItemCommand.preview.title,
            ItemCommand.paste.title,
            ItemCommand.copy.title,
            "",
            ItemCommand.share.title,
            ItemCommand.open.title,
            ItemCommand.revealInFinder.title,
        ])
        #expect(menu.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.isEnabled })

        for item in menu.items where !item.isSeparatorItem {
            (item.representedObject as? MenuAction)?.run()
        }
        #expect(calls == ["preview", "paste", "copy", "share", "open", "reveal"])

        let disabled = FileGroupMenuBuilder.makeMenu(
            target: host,
            isReachable: false,
            onPreview: {},
            onPaste: {},
            onCopy: {},
            onShare: { _ in },
            onOpen: {},
            onReveal: {}
        )
        #expect(disabled.items.filter { !$0.isSeparatorItem }.allSatisfy { !$0.isEnabled })
    }
}
