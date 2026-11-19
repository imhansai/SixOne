//
//  FilePathBar.swift
//  SixOne
//
//  预览底部路径行：可选择的绝对路径 + 整段复制按钮。
//

import AppKit
import SwiftUI

struct FilePathBar: View {
    let location: FileLocation
    /// 源文件是否仍可访问；false 时显示警告图标。
    var isReachable = true
    /// 整段复制；只写剪贴板，不写历史。
    let onCopy: (String) -> Void

    var body: some View {
        PanelFooterHint {
            HStack(spacing: 8) {
                if !isReachable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .appTooltip(String(
                            format: Localizer.string("File no longer exists: %@"),
                            location.name
                        ))
                        .accessibilityHidden(true)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(verbatim: location.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .textSelection(.enabled)
                        // 别加 accessibilityLabel：与 textSelection 组合会让 AX 查询递归爆栈。
                        .background(PathScrollMarker())
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

                // 贴合 11pt 行高，避免底部条变高。
                CopyTextButton(
                    size: 14,
                    text: location.path,
                    help: Localizer.string("Copy Path"),
                    onCopy: onCopy
                )
            }
            .padding(.horizontal, ClipboardLayout.previewInset)
        }
    }
}

extension NSUserInterfaceItemIdentifier {
    static let pathScrollView = NSUserInterfaceItemIdentifier("SixOne.PathScrollView")
}

/// 标记底层 NSScrollView，供测试定位。
private struct PathScrollMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { MarkerView() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class MarkerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            enclosingScrollView?.identifier = .pathScrollView
        }
    }
}
