//
//  PanelChrome.swift
//  SixOne
//  面板顶栏的通用外壳与细分隔线，列表页与预览页共用。

import SwiftUI

/// 面板内的横向细分隔线：统一颜色与水平内缩。
struct PanelHairlineDivider: View {
    var body: some View {
        Divider()
            .overlay(.primary.opacity(0.12))
            .padding(.horizontal, ClipboardLayout.headerHorizontalInset)
    }
}

/// 面板底部提示条：发丝线 + 11pt 次要文字，列表与预览共用同一高度。
struct PanelFooterHint<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHairlineDivider()
            content
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }
}

/// 面板顶栏外壳：统一高度、内边距、拖拽背景与分隔线。
struct PanelHeaderChrome<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, ClipboardLayout.headerHorizontalInset)
                .frame(height: ClipboardLayout.headerHeight)
                .background(PanelDragHandle())
            PanelHairlineDivider()
        }
    }
}
