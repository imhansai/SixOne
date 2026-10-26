//
//  ColorRepresentationTests.swift
//  SixOneTests
//  HSL / CMYK 的换算口径。

import AppKit
import Foundation
import Testing
@testable import SixOne

@Suite("颜色的其它写法")
struct ColorRepresentationTests {
    private func values(_ color: NSColor) throws -> [String: String] {
        let data = try #require(PasteboardFormat.colorData(of: color))
        let rows = try #require(ColorRepresentation.make(fromColorData: data))
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.label, $0.value) })
    }

    @Test("sRGB 纯红")
    func sRGBRed() throws {
        let rows = try values(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))

        #expect(rows["HSL"] == "hsl(0, 100%, 50%)")
        #expect(rows["CMYK"] == "0% 100% 100% 0%")
    }

    @Test("纯白：百分比与十六进制对得上")
    func white() throws {
        let rows = try values(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))

        #expect(rows["HSL"] == "hsl(0, 0%, 100%)")
        #expect(rows["CMYK"] == "0% 0% 0% 0%")
    }

    @Test("灰色：不出现 -0.0 这种负零写法")
    func grayHasNoNegativeZero() throws {
        let rows = try values(NSColor(white: 0.5, alpha: 1))

        for value in rows.values {
            #expect(!value.contains("-0.0"))
            #expect(!value.contains("nan"))
        }
        #expect(rows["HSL"] == "hsl(0, 0%, 50%)")
    }

    @Test("半透明：HSL 换成 hsla()，CMYK 不补（印刷里没有半透明油墨）")
    func translucentValues() throws {
        let rows = try values(NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.5))

        #expect(rows["HSLA"] == nil)  // 标签仍是 HSL，值用 hsla()
        #expect(rows["HSL"] == "hsla(220, 60%, 50%, 0.5)")
        #expect(rows["CMYK"] == "75% 50% 0% 20%")
    }

    @Test("两行都在，顺序固定（HSL、CMYK）")
    func rowOrder() throws {
        let data = try #require(PasteboardFormat.colorData(of: NSColor(srgbRed: 0.81, green: 0.4, blue: 0.56, alpha: 1)))
        let rows = try #require(ColorRepresentation.make(fromColorData: data))

        #expect(rows.map(\.label) == ["HSL", "CMYK"])
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test("宽色域来源：按 sRGB 归一化后给值，与预览里的十六进制同一份")
    func displayP3IsConvertedFromSRGB() throws {
        let p3 = NSColor(displayP3Red: 0.81, green: 0.4, blue: 0.56, alpha: 1)
        let rows = try values(p3)
        let sRGB = try values(NSColor(srgbRed: 0.81, green: 0.4, blue: 0.56, alpha: 1))

        #expect(rows["HSL"] != sRGB["HSL"])
        for value in rows.values {
            #expect(!value.contains("nan"))
            #expect(!value.contains("inf"))
        }
    }

    @Test("解不出颜色时为 nil")
    func rejectsGarbage() {
        #expect(ColorRepresentation.make(fromColorData: Data("hello".utf8)) == nil)
    }
}
