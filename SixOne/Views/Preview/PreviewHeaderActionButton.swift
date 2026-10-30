//
//  PreviewHeaderActionButton.swift
//  SixOne
//
//  预览顶栏图标按钮：1px 轮廓，悬停/按下反馈；菜单标签共用外观。
//

import SwiftUI

struct PreviewHeaderActionButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            PreviewHeaderIcon(systemImage: systemImage)
        }
        .buttonStyle(PreviewHeaderActionButtonStyle(isHovered: isHovered))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .appTooltip(help)
        .accessibilityLabel(help)
    }
}

/// 顶栏图标本体，菜单标签复用。
private struct PreviewHeaderIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 28, height: 28)
            .contentShape(Circle())
            .contentTransition(.symbolEffect(.replace))
    }
}

/// 菜单标签没有 Button 的按下态，只做悬停。
struct PreviewHeaderMenuLabel: View {
    let systemImage: String

    @State private var isHovered = false

    var body: some View {
        PreviewHeaderIcon(systemImage: systemImage)
            .background(PreviewHeaderActionBackground(isHovered: isHovered))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct PreviewHeaderActionButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                PreviewHeaderActionBackground(
                    isHovered: isHovered,
                    isPressed: configuration.isPressed
                )
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PreviewHeaderActionBackground: View {
    var isHovered = false
    var isPressed = false

    var body: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(isPressed ? 0.16 : (isHovered ? 0.08 : 0)))
            Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }
}
