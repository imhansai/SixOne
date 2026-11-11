//
//  DateFormattingTests.swift
//  SixOneTests

import Foundation
import Testing
@testable import SixOne

@Suite("时间格式化")
struct DateFormattingTests {
    @Test("预览时间戳使用固定格式")
    func previewTimestampUsesFixedFormat() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 11
        components.hour = 17
        components.minute = 34
        components.second = 15
        let date = try #require(Calendar.current.date(from: components))

        #expect(date.formattedTimestamp == "2026-11-11 17:34:15")
    }
}
