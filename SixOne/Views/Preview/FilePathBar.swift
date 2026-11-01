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
        HStack(spacing: 8) {
            if !isReachable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help(String(
                        format: Localizer.string("File no longer exists: %@"),
                        location.name
                    ))
                    .accessibilityHidden(true)
            }

            SelectablePathText(text: location.path)
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

extension NSUserInterfaceItemIdentifier {
    static let pathTextView = NSUserInterfaceItemIdentifier("SixOne.PathTextView")
}

/// 可选择、可横向滚动的单行路径。
struct SelectablePathText: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PathScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .allowed

        let textView = NSTextView()
        textView.identifier = .pathTextView
        configure(textView)
        textView.string = text
        context.coordinator.textView = textView
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        guard textView.string != text else { return }
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        scrollView.needsLayout = true
    }

    private func configure(_ textView: NSTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        textView.allowsUndo = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.maximumNumberOfLines = 1
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: ClipboardLayout.pathBarHeight)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: ClipboardLayout.pathBarHeight
        )
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .secondaryLabelColor
        textView.setAccessibilityLabel(Localizer.string("Path"))
    }

    final class Coordinator {
        var textView: NSTextView?
    }
}

/// 短路径铺满，长路径横向滚动。
final class PathScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let textView = documentView as? NSTextView,
              let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }
        layoutManager.ensureLayout(for: container)
        let usedWidth = layoutManager.usedRect(for: container).width
        let width = max(
            ceil(usedWidth) + textView.textContainerInset.width * 2 + 1,
            contentSize.width
        )
        let height = max(contentSize.height, ClipboardLayout.pathBarHeight)
        let target = NSSize(width: width, height: height)
        guard textView.frame.size != target else { return }
        textView.frame = NSRect(origin: .zero, size: target)
    }
}

