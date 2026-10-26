//
//  LinkPreview.swift
//  SixOne
//
//  链接条目预览：完整 URL 正文（可选中、查找、就地编辑）+ 协议/主机/端口底栏。
//

import AppKit
import SwiftUI

struct LinkPreview: View {
    let urlString: String?
    var isEditable = false
    var commitsOnExit = false
    var onEditingFinished: ((NSAttributedString) -> Void)?
    var onDirtyChange: ((Bool) -> Void)?
    var saveRequestID = 0

    @Environment(PanelContext.self) private var context
    @State private var isCopied = false

    /// 正文等宽：URL 里的 l/1/I、`.`/`,` 在比例字体下易看错。
    private static let bodyFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    var body: some View {
        if let urlString, !urlString.isEmpty {
            VStack(spacing: 0) {
                TextPreviewView(
                    // 指纹用正文本身：它就是链接条目的全部内容。
                    contentID: urlString,
                    attributedTextData: nil,
                    plainText: urlString,
                    font: Self.bodyFont,
                    isEditable: isEditable,
                    commitsOnExit: commitsOnExit,
                    onEditingFinished: onEditingFinished,
                    onDirtyChange: onDirtyChange,
                    saveRequestID: saveRequestID,
                    onCopyFallback: { [weak context] in context?.actions?.panelDidRequestCopyItem() },
                    onPasteFallback: { [weak context] in context?.actions?.panelDidRequestPasteItem() },
                    onEscape: { [weak context] in context?.actions?.panelDidRequestEscape() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let origin {
                    Divider()
                        .overlay(.primary.opacity(0.12))
                    originBar(origin)
                }
            }
        } else {
            PreviewUnavailable()
        }
    }

    private var origin: String? {
        Self.origin(of: urlString)
    }

    private func originBar(_ origin: String) -> some View {
        HStack(spacing: 8) {
            CopyableValueChip(label: nil, value: origin, onCopy: { copyOrigin(origin) })
            copiedNotice
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        // 与正文同一竖线（正文留白来自 TextPreviewView.textLinePadding）。
        .padding(.horizontal, TextPreviewView.textLinePadding)
    }

    private var copiedNotice: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
            Text(Localizer.string("Copied"))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(width: 58, alignment: .leading)
        .opacity(isCopied ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: isCopied)
    }

    /// 复制底栏内容：只写剪贴板、不动历史。
    private func copyOrigin(_ origin: String) {
        context.manager.copyPlainText(origin)
        isCopied = true
        Task {
            try? await Task.sleep(for: .seconds(PanelTiming.copiedFeedback))
            isCopied = false
        }
    }

    /// 从链接取协议 + 主机 + 端口；用 URLComponents 保留中文域名与 IPv6 原文，并丢弃凭据。
    nonisolated static func origin(of urlString: String?) -> String? {
        guard let urlString, let components = URLComponents(string: urlString),
              let scheme = components.scheme, !scheme.isEmpty,
              let host = components.host, !host.isEmpty else { return nil }
        let port = components.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}
