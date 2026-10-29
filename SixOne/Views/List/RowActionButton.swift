//
//  RowActionButton.swift
//  SixOne
//
//  行尾操作按钮外观：固定中性灰圆底，图标随系统外观与选中态取色。
//

import SwiftUI

/// 复制图标 / 对勾 / ⌘ 快捷编号共用；点击由 `RowCopyHitTarget` 处理，这里只负责画。
struct RowActionButton: View {
    enum Content {
        case copy(isCopied: Bool)
        case number(Int)
    }

    let content: Content
    let isActiveSelection: Bool
    var isPressed = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch content {
            case .copy(let isCopied):
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc.fill")
                    .font(.system(size: 12, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
            case .number(let number):
                Text(verbatim: "\(number)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(isActiveSelection ? Color.white : Color.primary)
        .frame(width: ClipboardLayout.rowCopyButtonSize, height: ClipboardLayout.rowCopyButtonSize)
        // 按下只改变圆底。
        .background {
            ZStack {
                Circle().fill(Self.fill(colorScheme: colorScheme))
                if isPressed {
                    Circle().fill(Self.pressedOverlay(colorScheme: colorScheme))
                }
            }
        }
    }

    /// 固定中性灰，选中蓝底上也不偏色。
    static func fill(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 90 / 255, green: 90 / 255, blue: 90 / 255).opacity(0.65)
            : Color(.sRGB, red: 200 / 255, green: 200 / 255, blue: 200 / 255).opacity(0.65)
    }

    /// 按下反馈按系统按钮习惯：浅色压暗、深色提亮；悬停不变色。
    static func pressedOverlay(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
    }
}

/// 点击已由命中目标收口，按钮本身不要再叠加按下反馈。
struct NoPressFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
