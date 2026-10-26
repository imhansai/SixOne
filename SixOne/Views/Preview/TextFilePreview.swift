//
//  TextFilePreview.swift
//  SixOne

import SwiftUI

/// 纯文本文件：后台读取后只读展示，失败回退 Quick Look，视图撤销即取消。
struct TextFilePreview: View {
    let url: URL
    @Environment(PanelContext.self) private var context
    @State private var content: Content = .loading

    var body: some View {
        view(for: content).task(id: url) {
            content = .loading
            let text = await TextFileReader.text(at: url)
            guard !Task.isCancelled else { return }
            content = text.map(Content.text) ?? .quickLook
        }
    }

    @ViewBuilder
    private func view(for content: Content) -> some View {
        switch content {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .text(let text):
            // 指纹取路径：预览期间不变，正文不会重复写入。
            TextPreviewView(
                contentID: url.path,
                attributedTextData: nil,
                plainText: text,
                onCopyFallback: { [weak context] in context?.actions?.panelDidRequestCopyItem() },
                onPasteFallback: { [weak context] in context?.actions?.panelDidRequestPasteItem() },
                onEscape: { [weak context] in context?.actions?.panelDidRequestEscape() }
            )
        case .quickLook:
            QuickLookPreview(url: url)
        }
    }

    private enum Content {
        case loading
        case text(String)
        case quickLook
    }
}
