//
//  RowTitleText.swift
//  SixOne
//  行标题：仅在文本真的被截断时显示完整标题 tooltip。

import AppKit
import SwiftUI

struct RowTitleText: View {
    let text: String
    let isActiveSelection: Bool
    /// tooltip 的第二行：文件路径或失联提示；没有就只显示标题。
    var detail: String?

    @State private var isTruncated = false
    @State private var availableWidth: CGFloat = 0

    private static let font = NSFont.systemFont(ofSize: 15.5)
    private var fullWidth: CGFloat {
        (text as NSString).size(withAttributes: [.font: Self.font]).width
    }

    private var tooltipText: String {
        guard let detail, !detail.isEmpty else { return text }
        return "\(text)\n\(detail)"
    }

    var body: some View {
        Text(text)
            .font(.system(size: 15.5))
            .foregroundStyle(isActiveSelection ? .white : .primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { setWidth(proxy.size.width) }
                        .onChange(of: proxy.size.width) { _, width in setWidth(width) }
                }
            }
            .onChange(of: text) { _, _ in
                updateTruncation(for: availableWidth)
            }
            .appTooltipIf(isTruncated, text: tooltipText)
    }

    private func setWidth(_ width: CGFloat) {
        availableWidth = width
        updateTruncation(for: width)
    }

    private func updateTruncation(for width: CGFloat) {
        guard width > 0 else { return }
        let truncated = fullWidth > width + 1
        if truncated != isTruncated {
            isTruncated = truncated
        }
    }
}
