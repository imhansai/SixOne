//
//  FilePathBar.swift
//  SixOne
//
//  预览底部的绝对路径条：可横向滚动的路径 + 拷贝按钮。
//

import SwiftUI

struct FilePathBar: View {
    let location: FileLocation
    /// 只写剪贴板，不写历史。
    let onCopy: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollablePathText(text: location.path)
                .frame(maxWidth: .infinity)

            CopyTextButton(
                text: location.path,
                help: Localizer.string("Copy Path"),
                onCopy: onCopy
            )
        }
        .frame(height: ClipboardLayout.pathBarHeight)
    }
}

/// 路径文本：隐藏滚动条，保留两指/Shift+滚轮横向滚动。
private struct ScrollablePathText: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 3)
        }
        .scrollIndicators(.hidden)
        // 路径变化时重建滚动视图，偏移回到起点。
        .id(text)
    }
}
