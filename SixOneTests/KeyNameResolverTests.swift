//
//  KeyNameResolverTests.swift
//  SixOneTests
//  键名解析：特殊键固定名，字母/标点随键盘布局，只断言可读。

import AppKit
import Carbon.HIToolbox
import Testing
@testable import SixOne

@Suite("按键显示名")
@MainActor
struct KeyNameResolverTests {
    @Test("特殊键用固定名字")
    func fixedNames() {
        let resolver = KeyNameResolver()

        #expect(resolver.name(for: UInt32(kVK_Space)) == "Space")
        #expect(resolver.name(for: UInt32(kVK_Return)) == "↩")
        #expect(resolver.name(for: UInt32(kVK_F1)) == "F1")
        #expect(resolver.name(for: UInt32(kVK_LeftArrow)) == "←")
    }

    @Test("字母与标点按当前布局翻译，至少不是 Key")
    func layoutTranslatedNames() {
        let resolver = KeyNameResolver()

        let letter = resolver.name(for: UInt32(kVK_ANSI_V))
        #expect(!letter.isEmpty)
        #expect(letter != "Key")
        #expect(letter.count == 1)

        let comma = resolver.name(for: UInt32(kVK_ANSI_Comma))
        #expect(!comma.isEmpty)
        #expect(comma != "Key")
    }

    @Test("菜单 key equivalent：特殊键映射到 AppKit 字符，字母转小写")
    func menuKeyEquivalents() {
        let resolver = KeyNameResolver()

        #expect(resolver.keyEquivalent(for: UInt32(kVK_Space)) == " ")
        #expect(resolver.keyEquivalent(for: UInt32(kVK_Return)) == "\r")
        #expect(resolver.keyEquivalent(for: UInt32(kVK_Escape)) == "\u{1b}")
        #expect(resolver.keyEquivalent(for: UInt32(kVK_F1))
            == String(UnicodeScalar(NSF1FunctionKey)!))
        #expect(resolver.keyEquivalent(for: UInt32(kVK_LeftArrow))
            == String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        #expect(resolver.keyEquivalent(for: UInt32(kVK_ANSI_Keypad1)) == nil,
                "小键盘无法用单个 key equivalent 准确表达")

        let letter = resolver.keyEquivalent(for: UInt32(kVK_ANSI_V))
        #expect(letter?.count == 1)
        #expect(letter == letter?.lowercased())
    }
}
