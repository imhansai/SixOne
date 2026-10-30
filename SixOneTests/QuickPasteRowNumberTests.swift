//
//  QuickPasteRowNumberTests.swift
//  SixOneTests
//  编号从完整可见范围首行起算，一屏最多 9 条。
//

import Testing
@testable import SixOne

@Suite("快速粘贴行编号")
@MainActor
struct QuickPasteRowNumberTests {
    @Test("编号随范围首行起算，范围外与超出上限不显示")
    func numberingWithinRange() {
        let range = 3...10
        #expect(QuickPaste.shortcutNumber(forRow: 3, in: range) == 1)
        #expect(QuickPaste.shortcutNumber(forRow: 10, in: range) == 8)
        #expect(QuickPaste.shortcutNumber(forRow: 2, in: range) == nil)
        #expect(QuickPaste.shortcutNumber(forRow: 11, in: range) == nil)
        #expect(QuickPaste.shortcutNumber(forRow: 0, in: nil) == nil)

        let long = 0...20
        #expect(QuickPaste.shortcutNumber(forRow: 8, in: long) == 9)
        #expect(QuickPaste.shortcutNumber(forRow: 9, in: long) == nil)
    }

}
