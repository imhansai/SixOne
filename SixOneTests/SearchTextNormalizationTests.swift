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

@Suite("别名归一化")
struct AliasNormalizationTests {
    @Test("空白折叠为单个空格，并去掉首尾")
    func collapsesWhitespace() {
        #expect(ClipboardItem.normalizedAlias("  工作\n\t邮箱  ") == "工作 邮箱")
    }

    @Test("全空白与 nil 视为未设置")
    func blankBecomesNil() {
        #expect(ClipboardItem.normalizedAlias(" \n\t") == nil)
        #expect(ClipboardItem.normalizedAlias(nil) == nil)
    }

    @Test("纯零宽字符视为未设置")
    func invisibleOnlyBecomesNil() {
        #expect(ClipboardItem.normalizedAlias("\u{200B}\u{FEFF}\u{200D}") == nil)
    }

    @Test("超长别名按上限截断")
    func truncatesToLimit() {
        let long = String(repeating: "a", count: AliasNormalizer.maxLength + 20)
        #expect(ClipboardItem.normalizedAlias(long)?.count == AliasNormalizer.maxLength)
    }

    @Test("空串按未设置处理")
    func emptyIsUnset() {
        #expect(AliasNormalizer.displayable("") == nil)
        #expect(AliasNormalizer.displayable(nil) == nil)
        #expect(AliasNormalizer.displayable("x") == "x")
    }

    @Test("纯占位字符视为未设置")
    func blankPlaceholdersBecomeNil() {
        #expect(ClipboardItem.normalizedAlias("\u{2800}\u{3164}") == nil)
    }
}
