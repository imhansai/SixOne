//
//  FilePathBar.swift
//  SixOne
//
//  预览底部路径行：可选择、可横向滚动的绝对路径 + 整段复制按钮。
//

import AppKit
import SwiftUI

/// 文件预览底部的路径行；非文件条目由调用方决定不渲染。
struct FilePathBar: View {
    let location: FileLocation
    /// 源文件当前是否仍在原位置；不在时前置警告图标。
    var isReachable = true
    /// 整段复制；只写剪贴板，不写历史。
    let onCopy: (String) -> Void
    /// 路径文本聚焦时 ⌘V 交回面板粘贴。
    let onPaste: () -> Void

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

            SelectablePathText(
                text: location.path,
                onCopyWhole: { onCopy(location.path) },
                onPaste: onPaste
            )
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

/// 只读、可选择、可横向滚动的单行路径文本。
struct SelectablePathText: NSViewRepresentable {
    let text: String
    let onCopyWhole: () -> Void
    let onPaste: () -> Void

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

        let textView = SelectablePathTextView()
        configure(textView)
        textView.onCopyWhole = onCopyWhole
        textView.onPasteFallback = onPaste
        textView.string = text
        context.coordinator.textView = textView
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        textView.onCopyWhole = onCopyWhole
        textView.onPasteFallback = onPaste
        guard textView.string != text else { return }
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        scrollView.needsLayout = true
    }

    private func configure(_ textView: SelectablePathTextView) {
        textView.identifier = SelectablePathTextView.viewIdentifier
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
        var textView: SelectablePathTextView?
    }
}

/// 文档宽度跟随文本：短路径铺满可视区，长路径可横向滚动。
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

/// 只读路径文本：无选区时 ⌘C 复制整段路径，⌘V 交回面板。
final class SelectablePathTextView: NSTextView {
    static let viewIdentifier = NSUserInterfaceItemIdentifier("SixOne.PreviewPathText")

    var onCopyWhole: (() -> Void)?
    var onPasteFallback: (() -> Void)?

    override func copy(_ sender: Any?) {
        if selectedRange().length == 0, let onCopyWhole {
            onCopyWhole()
            return
        }
        super.copy(sender)
    }

    override func paste(_ sender: Any?) {
        if let onPasteFallback {
            onPasteFallback()
            return
        }
        super.paste(sender)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(NSText.copy(_:)),
           selectedRange().length == 0,
           onCopyWhole != nil {
            return true
        }
        if item.action == #selector(NSText.paste(_:)), onPasteFallback != nil {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}
