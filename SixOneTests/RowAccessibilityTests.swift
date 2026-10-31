//
//  RowAccessibilityTests.swift
//  SixOneTests
//  行级无障碍文案：标题与详情用逗号连接，空详情只读标题。
//

import Testing
@testable import SixOne

@Suite("行无障碍文案")
@MainActor
struct RowAccessibilityTests {
    @Test("标题与详情组合")
    func composesLabel() {
        #expect(RowAccessibility.label(title: "报告.pdf", detail: "12 KB") == "报告.pdf, 12 KB")
        #expect(RowAccessibility.label(title: "文本", detail: "") == "文本")
    }
}
