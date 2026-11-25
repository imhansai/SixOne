//
//  HistoryFilterPresentation.swift
//  SixOne
//
//  筛选条件的共用展示：弹层与筛选条使用同一套标题与图标。
//

import AppKit
import SwiftUI

enum HistoryFilterPresentation {
    static func kindTitle(_ kind: ClipboardItemKind) -> String {
        switch kind {
        case .text: Localizer.string("Text")
        case .image: Localizer.string("Image")
        case .file: Localizer.string("File")
        case .link: Localizer.string("Link")
        case .color: Localizer.string("Color")
        }
    }

    static func kindSymbol(_ kind: ClipboardItemKind) -> String {
        switch kind {
        case .text: "doc.text"
        case .image: "photo"
        case .file: "doc"
        case .link: "link"
        case .color: "paintpalette"
        }
    }

    static func dateTitle(_ range: HistoryDateRange) -> String {
        switch range {
        case .today: Localizer.string("Today")
        case .yesterday: Localizer.string("Yesterday")
        case .last7Days: Localizer.string("Last 7 Days")
        case .last30Days: Localizer.string("Last 30 Days")
        case .older: Localizer.string("Older")
        }
    }

    static func dateSymbol(_ range: HistoryDateRange) -> String {
        switch range {
        case .today: "sun.max"
        case .yesterday: "moon"
        case .last7Days: "calendar"
        case .last30Days: "calendar.badge.clock"
        case .older: "archivebox"
        }
    }
}

/// 文字是否超出展示宽度；只有被截断时才需要 tooltip。
enum FilterTextFit {
    static func isTruncated(
        _ text: String,
        maxWidth: CGFloat,
        fontSize: CGFloat,
        weight: NSFont.Weight
    ) -> Bool {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return width > maxWidth + 0.5
    }
}

/// 筛选 chip 的共用配色；弹层与活跃筛选条保持一致。
struct FilterChipAppearance {
    var isSelected: Bool
    var isIncreasedContrast: Bool

    var fill: Color {
        if isSelected {
            return PanelSelectionAppearance.active.opacity(isIncreasedContrast ? 0.30 : 0.22)
        }
        return Color.primary.opacity(isIncreasedContrast ? 0.07 : 0.05)
    }

    var border: Color {
        isSelected
            ? PanelSelectionAppearance.active
            : Color.primary.opacity(isIncreasedContrast ? 0.18 : 0.09)
    }

    var borderWidth: CGFloat {
        isSelected ? (isIncreasedContrast ? 2 : 1.5) : 1
    }

    var foreground: Color {
        isSelected ? .primary : Color.primary.opacity(isIncreasedContrast ? 0.85 : 0.72)
    }
}
