//
//  LinkPreview.swift
//  SixOne
//
//  链接条目预览：完整 URL 正文（可选中、查找、就地编辑）。
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

    /// 正文等宽：URL 里的 l/1/I、`.`/`,` 在比例字体下易看错。
    private static let bodyFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    var body: some View {
        if let urlString, !urlString.isEmpty {
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
        } else {
            PreviewUnavailable()
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
