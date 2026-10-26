//
//  ColorPreview.swift
//  SixOne
//
//  颜色条目预览：色块、十六进制与其它写法，点按即复制。
//

import AppKit
import SwiftUI

struct ColorPreview: View {
    let colorData: Data?

    private static let swatchSize: CGFloat = 200

    @Environment(PanelContext.self) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedNotice: String?
    @State private var noticeWork: DispatchWorkItem?

    private var rgb: NSColor? {
        guard let colorData else { return nil }
        return PasteboardFormat.color(from: colorData)?.usingColorSpace(.sRGB)
    }

    var body: some View {
        if let rgb, let hex = colorData.flatMap(PasteboardFormat.hexString(ofColorData:)),
           let css = colorData.flatMap(PasteboardFormat.cssRGBString(ofColorData:)) {
            VStack(spacing: 20) {
                swatch(rgb)
                VStack(spacing: 8) {
                    valueChip(hex, label: nil, emphasized: true)
                    valueChip(css, label: nil)
                }
                if !representations.isEmpty {
                    otherRepresentations
                }
                // 提示行占固定高度，出现/消失不推动上方内容。
                noticeLine
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PreviewUnavailable()
        }
    }

    private var otherRepresentations: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 5) {
            ForEach(Array(stride(from: 0, to: representations.count, by: 2)), id: \.self) { start in
                GridRow {
                    representationChip(representations[start])
                    if start + 1 < representations.count {
                        representationChip(representations[start + 1])
                    }
                }
            }
        }
    }

    private func representationChip(_ representation: ColorRepresentation) -> some View {
        CopyableValueChip(
            label: representation.label,
            value: representation.value,
            labelWidth: 40
        ) {
            copy(representation.value, label: representation.label)
        }
    }

    private var representations: [ColorRepresentation] {
        colorData.flatMap(ColorRepresentation.make(fromColorData:)) ?? []
    }

    private func swatch(_ rgb: NSColor) -> some View {
        ZStack {
            // 半透明色垫棋盘格，否则看不出这是带透明度的同一种颜色。
            if rgb.alphaComponent < 0.999 {
                checkerboard
            }
            Color(nsColor: rgb)
        }
        .frame(width: Self.swatchSize, height: Self.swatchSize)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var checkerboard: some View {
        Canvas { canvas, size in
            let square: CGFloat = 8
            let base = colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
            let alternate = colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.11)
            canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))

            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var column = 0
                var x: CGFloat = 0
                while x < size.width {
                    if (row + column).isMultiple(of: 2) {
                        canvas.fill(
                            Path(CGRect(x: x, y: y, width: square, height: square)),
                            with: .color(alternate)
                        )
                    }
                    column += 1
                    x += square
                }
                row += 1
                y += square
            }
        }
    }

    private func valueChip(_ value: String, label: String?, emphasized: Bool = false) -> some View {
        CopyableValueChip(
            label: label,
            value: value,
            emphasized: emphasized
        ) {
            copy(value, label: label)
        }
    }

    private var noticeLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
            Text(copiedNotice ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .opacity(copiedNotice == nil ? 0 : 1)
        .frame(height: 14)
        .animation(.easeOut(duration: 0.15), value: copiedNotice)
    }

    private func copy(_ value: String, label: String?) {
        // 只写剪贴板、不动历史：复制的是其中一个色值。
        context.manager.copyPlainText(value)
        let shown = [label, value].compactMap { $0 }.joined(separator: " ")
        copiedNotice = String(format: Localizer.string("%@ copied"), shown)

        noticeWork?.cancel()
        let work = DispatchWorkItem { copiedNotice = nil }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PanelTiming.colorCopiedNotice, execute: work)
    }

    /// 预览副标题：色彩空间 + 不透明度，这两项正文的色值与 RGB 都给不出。
    static func subtitle(forColorData data: Data?) -> String? {
        guard let data, let color = PasteboardFormat.color(from: data) else { return nil }
        let space = PasteboardFormat.shortColorSpaceName(of: color)
        let alpha = color.alphaComponent
        let opacity = alpha >= 0.999
            ? Localizer.string("Opaque")
            : String(format: Localizer.string("%@ opaque"), "\(Int((alpha * 100).rounded()))%")
        return "\(space) · \(opacity)"
    }
}
