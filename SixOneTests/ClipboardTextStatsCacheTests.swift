//
//  ClipboardTextStatsCacheTests.swift
//  SixOneTests
//  文本统计：字符、词与行数的计数规则。
//

import Foundation
import Testing
@testable import SixOne

@Suite("文本统计")
struct TextStatsTests {
    @Test("LF 逐行计数")
    func countsLineFeed() {
        #expect(TextStats.compute(from: "a\nb") == TextStats(characters: 3, words: 2, lines: 2))
        #expect(TextStats.compute(from: "a\nb\nc") == TextStats(characters: 5, words: 3, lines: 3))
    }

    @Test("CRLF 只算一次换行")
    func countsCarriageReturnLineFeedOnce() {
        #expect(TextStats.compute(from: "a\r\nb") == TextStats.compute(from: "a\nb"))
        #expect(TextStats.compute(from: "a\r\nb\r\nc") == TextStats.compute(from: "a\nb\nc"))
    }

    @Test("单独的 CR 仍算一行")
    func countsStandaloneCarriageReturn() {
        #expect(TextStats.compute(from: "a\rb") == TextStats(characters: 3, words: 2, lines: 2))
    }

    @Test("Unicode 行分隔符按行计数")
    func countsUnicodeLineSeparators() {
        #expect(
            TextStats.compute(from: "a\u{2028}b\u{2029}c")
                == TextStats(characters: 5, words: 3, lines: 3)
        )
    }
}
