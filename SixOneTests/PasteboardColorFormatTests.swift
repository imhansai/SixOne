//
//  PasteboardColorFormatTests.swift
//  SixOneTests
//  颜色字节形态：库存归档本体，写回走 `setPropertyList`，否则别家应用会崩。

import AppKit
import Foundation
import Testing
@testable import SixOne

@Suite("颜色的剪贴板形态")
struct PasteboardColorFormatTests {
    private let color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)

    @Test("色板写出的字节：剥成归档本体，色值照旧读得出")
    func normalizesPanelPayload() throws {
        let archive = try #require(PasteboardFormat.colorData(of: color))
        let item = NSPasteboardItem()
        item.setPropertyList(archive, forType: .color)
        let raw = try #require(item.data(forType: .color))

        #expect(PasteboardFormat.colorArchive(from: raw) == archive)
        #expect(PasteboardFormat.hexString(ofColorData: raw) == "#3366CC")
    }

    @Test("直接 setData 的裸归档：同样归一成归档本体")
    func normalizesBareArchive() throws {
        let archive = try #require(PasteboardFormat.colorData(of: color))

        #expect(PasteboardFormat.colorArchive(from: archive) == archive)
        #expect(PasteboardFormat.hexString(ofColorData: archive) == "#3366CC")
    }

    @Test("不是颜色的字节：归一与解析都返回 nil，不误判")
    func rejectsGarbage() {
        let garbage = Data("hello".utf8)

        #expect(PasteboardFormat.colorArchive(from: garbage) == nil)
        #expect(PasteboardFormat.color(from: garbage) == nil)
    }

    @Test("十六进制与 RGB 分量来自同一组四舍五入值")
    func componentsMatchHex() throws {
        let data = try #require(PasteboardFormat.colorData(of: color))
        let components = try #require(PasteboardFormat.sRGBComponents(ofColorData: data))

        #expect(components.red == 0x33)
        #expect(components.green == 0x66)
        #expect(components.blue == 0xCC)
        #expect(components.alpha == 1)
        #expect(PasteboardFormat.hexString(ofColorData: data) == "#3366CC")
        #expect(PasteboardFormat.cssRGBString(ofColorData: data) == "rgb(51, 102, 204)")
    }

    @Test("半透明颜色：十六进制补到 8 位，rgb() 补上 alpha")
    func translucentValuesCarryAlpha() throws {
        let data = try #require(
            PasteboardFormat.colorData(of: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.5))
        )
        let components = try #require(PasteboardFormat.sRGBComponents(ofColorData: data))

        #expect(components.alpha == 0.5)
        #expect(PasteboardFormat.hexString(ofColorData: data) == "#3366CC80")
        // 用 rgba()：CSS3 起普遍支持，rgb(…, a) 是 Color 4 才有的写法。
        #expect(PasteboardFormat.cssRGBString(ofColorData: data) == "rgba(51, 102, 204, 0.5)")
    }

    @Test("透明度文本：两位小数、去掉尾随零")
    func alphaTextFormatting() {
        #expect(PasteboardFormat.alphaText(0.5) == "0.5")
        #expect(PasteboardFormat.alphaText(0.25) == "0.25")
        #expect(PasteboardFormat.alphaText(1.0 / 3.0) == "0.33")
        #expect(PasteboardFormat.alphaText(0.05) == "0.05")
    }

    @Test("色彩空间短名：常见的给短名，其余回落到系统名")
    func colorSpaceShortNames() {
        #expect(PasteboardFormat.shortColorSpaceName(of: color) == "sRGB")
        #expect(PasteboardFormat.shortColorSpaceName(
            of: NSColor(displayP3Red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        ) == "Display P3")
        #expect(PasteboardFormat.shortColorSpaceName(
            of: NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        ) == "Generic RGB")
    }

    @Test("颜色预览副标题：带色彩空间，且区分不透明与半透明")
    func colorPreviewSubtitle() throws {
        // 系统色问 colorSpace 会抛异常，副标题须自行兜住。
        let opaque = try #require(PasteboardFormat.colorData(of: .systemPink))
        let half = try #require(PasteboardFormat.colorData(of: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5)))

        let opaqueText = try #require(ColorPreview.subtitle(forColorData: opaque))
        let halfText = try #require(ColorPreview.subtitle(forColorData: half))

        #expect(opaqueText.contains("sRGB"))
        #expect(halfText.contains("sRGB"))
        #expect(halfText.contains("50%"))
        #expect(!opaqueText.contains("%"))
        #expect(ColorPreview.subtitle(forColorData: nil) == nil)
    }

    @Test("写回形态：setPropertyList 让标准读法读得到")
    func writeShapeIsReadableByStandardAPI() throws {
        let archive = try #require(PasteboardFormat.colorData(of: color))
        let item = NSPasteboardItem()

        item.setPropertyList(archive, forType: .color)

        let payload = try #require(item.propertyList(forType: .color) as? Data)
        #expect(NSColor(pasteboardPropertyList: payload, ofType: .color) != nil)
        #expect(PasteboardFormat.hexString(ofColorData: payload) == "#3366CC")
    }

    @Test("裸归档直接 setData：读方拿到的是字典，标准读法读不到（写回不许这么写）")
    func rawArchiveShapeIsNotAcceptable() throws {
        let archive = try #require(PasteboardFormat.colorData(of: color))
        let wrong = NSPasteboardItem()
        wrong.setData(archive, forType: .color)

        // 标准读法要 NSData，字典交给 NSColor 会崩（实测），故只钉拿不到 NSData。
        #expect(wrong.propertyList(forType: .color) as? Data == nil)
        // 自身读法仍须认裸归档：外部应用与 3.0.0 前入库的字节都可能长这样。
        let raw = try #require(wrong.data(forType: .color))
        #expect(PasteboardFormat.hexString(ofColorData: raw) == "#3366CC")
    }
}
