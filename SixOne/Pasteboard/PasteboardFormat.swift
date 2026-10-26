//
//  PasteboardFormat.swift
//  SixOne
//
//  剪贴板图像格式知识：扩展名判定、粘贴板类型映射与只读容器头的位图校验。
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PasteboardFormat {
    /// 按图片条目处理的扩展名（小写）；扩展它会改变条目分类。
    static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tif", "tiff", "webp", "heic",
    ]

    /// 位图粘贴板类型：TIFF 或 PNG。
    static func pasteboardType(forContentType contentType: String?) -> NSPasteboard.PasteboardType {
        switch (contentType ?? "").uppercased() {
        case "TIFF", "TIF": return .tiff
        default: return .png
        }
    }

    /// 是否可用位图；只解析容器头不解码像素，避免主线程轮询卡顿。
    static func isBitmap(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              UTType(type as String)?.conforms(to: .image) == true else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// 首选扩展名；读不出回落 png。
    static func fileExtension(ofBitmap data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let ext = UTType(type as String)?.preferredFilenameExtension else { return "png" }
        return ext
    }

    /// 把颜色字节归一成 NSColor 归档本体，收敛色板与裸归档两种形态。
    static func colorArchive(from data: Data) -> Data? {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let archived = plist as? Data,
           NSColor(pasteboardPropertyList: archived, ofType: .color) != nil {
            return archived
        }
        return NSColor(pasteboardPropertyList: data, ofType: .color) != nil ? data : nil
    }

    /// 归档本体解回 `NSColor`；先归一再解，避免标准读法收到 NSDictionary 崩溃。
    static func color(from data: Data) -> NSColor? {
        guard let archived = colorArchive(from: data) else { return nil }
        return NSColor(pasteboardPropertyList: archived, ofType: .color)
    }

    /// 归档成标准颜色负载；与色板来源一致，可跨来源去重。
    static func colorData(of color: NSColor) -> Data? {
        color.pasteboardPropertyList(forType: .color) as? Data
    }

    /// 颜色的大写十六进制值（sRGB）；带透明度用 8 位 `#RRGGBBAA` 以区分。
    static func hexString(ofColorData data: Data) -> String? {
        guard let components = sRGBComponents(ofColorData: data) else { return nil }
        guard components.alpha < 0.999 else {
            return String(format: "#%02X%02X%02X", components.red, components.green, components.blue)
        }
        return String(
            format: "#%02X%02X%02X%02X",
            components.red,
            components.green,
            components.blue,
            Int((components.alpha * 255).rounded())
        )
    }

    /// sRGB 归一化分量与透明度；各写法共用。
    static func sRGBComponents(ofColorData data: Data) -> (red: Int, green: Int, blue: Int, alpha: Double)? {
        guard let color = color(from: data),
              let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return (
            red: Int(round(rgb.redComponent * 255)),
            green: Int(round(rgb.greenComponent * 255)),
            blue: Int(round(rgb.blueComponent * 255)),
            alpha: Double(rgb.alphaComponent)
        )
    }

    /// CSS `rgb()`/`rgba()`；带 alpha 用 `rgba()`，兼容 CSS3。
    static func cssRGBString(ofColorData data: Data) -> String? {
        guard let components = sRGBComponents(ofColorData: data) else { return nil }
        let rgb = "\(components.red), \(components.green), \(components.blue)"
        guard components.alpha < 0.999 else { return "rgb(\(rgb))" }
        return "rgba(\(rgb), \(alphaText(components.alpha)))"
    }

    /// 透明度写成 CSS 数：两位小数、去尾随 0。
    static func alphaText(_ alpha: Double) -> String {
        var text = String(format: "%.2f", alpha)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// 色彩空间短名（预览副标题用）；目录色与图案色按 sRGB 报，避免 `colorSpace` 抛异常。
    static func shortColorSpaceName(of color: NSColor) -> String {
        switch color.type {
        case .catalog, .pattern: return "sRGB"
        default: break
        }
        let space = color.colorSpace
        if space == .sRGB { return "sRGB" }
        if space == .displayP3 { return "Display P3" }
        if space == .genericRGB { return "Generic RGB" }
        if space == .deviceRGB { return "Device RGB" }
        return space.localizedName ?? "RGB"
    }
}
