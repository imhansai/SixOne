//
//  TextFilePreview.swift
//  SixOne

import SwiftUI

/// 文本文件预览：后台读取；超上限只显示开头并标注截断。
struct TextFilePreview: View {
    let url: URL
    @Environment(PanelContext.self) private var context
    @State private var content: Content = .loading

    var body: some View {
        view(for: content).task(id: url) {
            content = .loading
            let file = await TextFileReader.content(at: url)
            guard !Task.isCancelled else { return }
            content = file.map(Content.text) ?? .quickLook
        }
    }

    @ViewBuilder
    private func view(for content: Content) -> some View {
        switch content {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .text(let file):
            ZStack(alignment: .bottom) {
                TextPreviewView(
                    // 指纹取路径：预览期间不变，正文不会重复写入。
                    contentID: url.path,
                    attributedTextData: nil,
                    plainText: file.text,
                    onEscape: { [weak context] in context?.editingActions?.panelDidRequestEscape() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if file.isTruncated || file.isCharacterTruncated {
                    truncationBadge(file)
                }
            }
        case .quickLook:
            QuickLookPreview(url: url)
        }
    }

    private func truncationBadge(_ file: TextFileContent) -> some View {
        Text(truncationMessage(for: file))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.regularMaterial))
            .padding(.bottom, 8)
            .allowsHitTesting(false)
    }

    private func truncationMessage(for file: TextFileContent) -> String {
        if file.isCharacterTruncated {
            return String(
                format: Localizer.string("Showing the first %@ characters of a %@ file."),
                TextPreviewLimit.displayedCharacters.formatted(),
                ByteCountFormatting.string(fromByteCount: file.totalBytes)
            )
        }
        return String(
            format: Localizer.string("Showing the first %@ of a %@ file."),
            ByteCountFormatting.string(fromByteCount: Int64(TextFileReader.maxReadBytes)),
            ByteCountFormatting.string(fromByteCount: file.totalBytes)
        )
    }

    private enum Content {
        case loading
        case text(TextFileContent)
        case quickLook
    }
}
