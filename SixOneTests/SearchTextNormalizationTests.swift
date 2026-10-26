//
//  SearchTextNormalizationTests.swift
//  SixOneTests

import Testing
@testable import SixOne

@Suite("搜索快照的单行化")
struct SearchTextNormalizationTests {
    @Test("换行类字符各转一个空格", arguments: [0x0A, 0x0D, 0x0B, 0x0C, 0x85, 0x2028, 0x2029])
    func lineSeparatorsBecomeSpaces(scalar: Int) {
        let separator = String(UnicodeScalar(scalar)!)
        #expect(ClipboardItem.normalizedSearchText("a\(separator)b") == "a b")
    }

    @Test("CRLF 是逐字符处理，落成两个空格")
    func crlfBecomesTwoSpaces() {
        #expect(ClipboardItem.normalizedSearchText("a\r\nb") == "a  b")
    }

    @Test("空格与 Tab 原样保留，也不去首尾空白")
    func keepsSpacesAndTabs() {
        #expect(ClipboardItem.normalizedSearchText(" a\tb ") == " a\tb ")
    }

    @Test("全空白与 nil 视为无搜索文本")
    func blankBecomesNil() {
        #expect(ClipboardItem.normalizedSearchText(" \t\n") == nil)
        #expect(ClipboardItem.normalizedSearchText(nil) == nil)
    }

    @Test("文本条目捕获时即写入搜索快照")
    func textItemFillsSnapshotOnInit() {
        let item = ClipboardItem(kind: .text, text: "第一行\n第二行")
        #expect(item.searchText == "第一行 第二行")
    }
}
