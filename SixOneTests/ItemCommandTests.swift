//
//  ItemCommandTests.swift
//  SixOneTests
//  条目动作词汇表：菜单顺序、备用项归属、标题非空。

import Testing
@testable import SixOne

@Suite("条目动作词汇表")
@MainActor
struct ItemCommandTests {
    @Test("文本条目：粘贴 / 纯文本粘贴 / 拷贝 / 纯文本拷贝 / 删除")
    func textRowLayout() {
        #expect(ItemCommand.rowMenuLayout(for: .text) == [
            .command(.paste),
            .command(.pasteAsPlainText),
            .command(.copy),
            .command(.copyAsPlainText),
            .separator,
            .command(.delete),
        ])
    }

    @Test("图片条目：没有纯文本版本，多出分享与打开")
    func imageRowLayout() {
        #expect(ItemCommand.rowMenuLayout(for: .image) == [
            .command(.paste),
            .command(.copy),
            .separator,
            .command(.share),
            .command(.open),
            .separator,
            .command(.delete),
        ])
    }

    @Test("文件条目与图片条目同构（都只有整条的文件动作）")
    func fileRowLayoutMatchesImage() {
        #expect(ItemCommand.rowMenuLayout(for: .file) == ItemCommand.rowMenuLayout(for: .image))
    }

    @Test("链接条目：与图片/文件同构（可打开、可分享）")
    func linkRowLayout() {
        #expect(ItemCommand.rowMenuLayout(for: .link) == [
            .command(.paste),
            .command(.copy),
            .separator,
            .command(.share),
            .command(.open),
            .separator,
            .command(.delete),
        ])
    }

    @Test("颜色条目：没有打开/分享，只有粘贴/拷贝/删除")
    func colorRowLayout() {
        #expect(ItemCommand.rowMenuLayout(for: .color) == [
            .command(.paste),
            .command(.copy),
            .separator,
            .command(.delete),
        ])
    }

    @Test("每个动作都有非空标题，且 ⇧ 备用项成对出现")
    func everyCommandHasTitle() {
        for command in ItemCommand.allCases {
            #expect(!command.title.isEmpty)
            if command.isAlternate {
                #expect(command.modifiers.contains(.command))
                #expect(command.modifiers.contains(.shift))
                #expect(command.keyEquivalent != nil)
            }
        }
    }

    @Test("只有整条文件动作需要「文件还在」这一前提")
    func reachableFileRequirement() {
        for command in ItemCommand.allCases {
            let expected = command == .share || command == .open
            #expect(command.requiresReachableFile == expected)
        }
    }
}
