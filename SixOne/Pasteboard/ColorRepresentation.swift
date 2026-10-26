//
//  ColorRepresentation.swift
//  SixOne
//
//  颜色的其它写法（HSL、CMYK），供预览排成可点复制的行；全部基于 sRGB 归一化颜色。
//

import AppKit
import Foundation

nonisolated struct ColorRepresentation: Identifiable, Sendable {
    /// 行标签（HSL / CMYK），不进本地化表。
    let label: String
    /// 显示与复制共用的文本。
    let value: String

    var id: String { label }

    /// 算出全套写法；颜色字节解不出时为 nil。
    static func make(fromColorData data: Data) -> [ColorRepresentation]? {
        guard let base = PasteboardFormat.color(from: data),
              let color = base.usingColorSpace(.sRGB) else { return nil }

        let red = color.redComponent
        let green = color.greenComponent
        let blue = color.blueComponent
        let (hue, saturation, lightness) = hsl(red, green, blue)
        let alpha = Double(color.alphaComponent)
        let hslComponents = "\(degrees(hue)), \(percent(saturation)), \(percent(lightness))"
        let hslValue = alpha < 0.999
            ? "hsla(\(hslComponents), \(PasteboardFormat.alphaText(alpha)))"
            : "hsl(\(hslComponents))"
        return [
            ColorRepresentation(label: "HSL", value: hslValue),
            ColorRepresentation(label: "CMYK", value: cmyk(red, green, blue)),
        ]
    }

    // MARK: - 色彩模型换算

    /// sRGB → HSL（色相 0–360、饱和度与亮度 0–1）。
    private static func hsl(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        guard delta > 0 else { return (0, 0, lightness) }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        let hue: CGFloat
        switch maximum {
        case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        return (normalizedDegrees(hue * 60), saturation, lightness)
    }

    /// sRGB → CMYK 简易换算：K 取最亮通道的补，其余按比例摊。
    private static func cmyk(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> String {
        let black = 1 - max(red, green, blue)
        guard black < 1 else { return "0% 0% 0% 100%" }
        let scale = 1 - black
        return [
            percent((1 - red - black) / scale),
            percent((1 - green - black) / scale),
            percent((1 - blue - black) / scale),
            percent(black),
        ].joined(separator: " ")
    }

    private static func normalizedDegrees(_ value: CGFloat) -> CGFloat {
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    // MARK: - 数字格式

    private static func degrees(_ value: CGFloat) -> String {
        "\(Int(value.rounded()))"
    }

    private static func percent(_ value: CGFloat, digits: Int = 0) -> String {
        "\(number(value * 100, digits: digits))%"
    }

    private static func number(_ value: CGFloat, digits: Int) -> String {
        // 四舍五入可能得到 -0.0；两支都保持 CGFloat，避免被推断成 Int 传给 %f。
        let scale = pow(10, CGFloat(digits))
        let rounded = (value * scale).rounded() / scale
        let normalized: CGFloat = rounded == 0 ? CGFloat.zero : rounded
        return String(format: "%.\(digits)f", normalized)
    }
}
