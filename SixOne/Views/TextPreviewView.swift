//
//  TextPreviewView.swift
//  SixOne

import AppKit
import SwiftUI

/// 文本条目预览与编辑：NSTextView 保留 RTF 格式，退编辑时回调宿主保存。
/// 落盘只走「退出编辑」；收起面板是挂起，关闭预览算放弃本次编辑。
struct TextPreviewView: NSViewRepresentable {
    static let textViewIdentifier = NSUserInterfaceItemIdentifier("SixOne.PreviewTextView")

    private static let defaultTextFont = NSFont.systemFont(ofSize: 14)

    /// 内容指纹：变化时刷新，避免比较超大 Data。
    let contentID: String
    let attributedTextData: Data?
    let plainText: String?
    /// 兜底字体；链接预览传等宽字体，避免 l/1/I 等字形混淆。
    var font: NSFont = defaultTextFont
    var showsFormatting: Bool = true
    var isEditable: Bool = false
    /// 退出编辑时是否保存；false 表示放弃（关闭预览时只清基线、不回调）。
    var commitsOnExit: Bool = false
    /// 退出编辑时回调结果，内容无净变化则不回调。
    var onEditingFinished: ((NSAttributedString) -> Void)?
    /// 正文相对编辑基线是否有净改动；Esc/取消据此确认。
    var onDirtyChange: ((Bool) -> Void)?
    /// ⌘S 请求：递增即保存，不退出编辑态。
    var saveRequestID = 0
    var onCopyFallback: (() -> Void)?
    var onPasteFallback: (() -> Void)?
    var onEscape: (() -> Void)?

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = Self.makeTextView()
        textView.identifier = Self.textViewIdentifier
        textView.delegate = context.coordinator
        textView.onCopyFallback = onCopyFallback
        textView.onPasteFallback = onPasteFallback
        textView.onEscape = onEscape
        context.coordinator.onDirtyChange = onDirtyChange
        context.coordinator.lastSaveRequestID = saveRequestID
        textView.isRichText = true
        textView.isSelectable = true
        textView.isEditable = isEditable
        // 「字体」子菜单跟随编辑态：只读需 false 否则菜单点不动；编辑态需 true 否则字体面板与粗体/斜体失灵。
        textView.usesFontPanel = isEditable
        // 撤销栈由 Coordinator 提供，与搜索框 field editor 隔离。
        textView.allowsUndo = true
        textView.isAutomaticLinkDetectionEnabled = false
        // 深色外观下自动提亮来源中的深色文字。
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        // 内嵌查找栏，适配非激活 borderless 面板。
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        Self.applyContent(
            to: textView,
            attributedTextData: attributedTextData,
            plainText: plainText,
            font: font,
            showsFormatting: isEditable || showsFormatting
        )
        if isEditable {
            context.coordinator.beginEditing(in: textView)
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        // 滚动条样式交给 AppKit 跟随系统设置，不写死也不推导。
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.observeTextStorage(of: textView)
        context.coordinator.lastContentID = contentID
        context.coordinator.lastShowsFormatting = isEditable || showsFormatting

        // 进预览即聚焦，⌘F/A/C 经响应链直达；已离开窗口则不抢。
        DispatchQueue.main.async { [weak textView] in
            guard let textView, textView.window != nil else { return }
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.onEditingFinished = onEditingFinished
        context.coordinator.onDirtyChange = onDirtyChange
        textView.onCopyFallback = onCopyFallback
        textView.onPasteFallback = onPasteFallback
        textView.onEscape = onEscape

        // 编辑态切换：进入建立基线，退出把最终内容交给宿主保存。
        let wasEditable = textView.isEditable
        if isEditable != wasEditable {
            textView.isEditable = isEditable
            textView.usesFontPanel = isEditable
            if isEditable {
                // 进入编辑先装回富文本，必须在 beginEditing 取基线前完成。
                if !context.coordinator.lastShowsFormatting {
                    Self.applyContent(
                        to: textView,
                        attributedTextData: attributedTextData,
                        plainText: plainText,
                        font: font,
                        showsFormatting: true
                    )
                }
                context.coordinator.lastShowsFormatting = true
                context.coordinator.beginEditing(in: textView)
                // 落位会强制布局，须挪到下一轮 runloop，否则触发 AttributeGraph cycle；先落位再聚焦。
                DispatchQueue.main.asyncAfter(deadline: .now()) { [weak textView] in
                    guard let textView, textView.window != nil else { return }
                    context.coordinator.placeInsertionPointForEditing(in: textView)
                    textView.window?.makeFirstResponder(textView)
                }
            } else {
                context.coordinator.finishEditing(in: textView, commit: commitsOnExit)
                // 纯文本取视图最终正文，等宿主写回前不闪旧内容。
                if showsFormatting {
                    // 视图里已是写回的富文本，无需重建。
                    context.coordinator.lastShowsFormatting = true
                } else {
                    Self.applyContent(
                        to: textView,
                        attributedTextData: nil,
                        plainText: textView.string,
                        font: font,
                        showsFormatting: false
                    )
                    context.coordinator.lastShowsFormatting = false
                }
            }
        }

        // ⌘S：保存但留在编辑态；放在指纹判断前，避免同轮 contentID 变化漏掉。
        if saveRequestID != context.coordinator.lastSaveRequestID {
            context.coordinator.lastSaveRequestID = saveRequestID
            if isEditable {
                context.coordinator.saveEditing(in: textView)
            }
        }

        // 显示格式变化时指纹不变，单独比较显示模式重载。
        let displaysFormatting = isEditable || showsFormatting
        if !isEditable, displaysFormatting != context.coordinator.lastShowsFormatting {
            context.coordinator.lastShowsFormatting = displaysFormatting
            Self.applyContent(
                to: textView,
                attributedTextData: attributedTextData,
                plainText: plainText,
                font: font,
                showsFormatting: displaysFormatting
            )
        }

        guard contentID != context.coordinator.lastContentID else { return }
        context.coordinator.lastContentID = contentID

        // 刚退出编辑：视图已是写回内容，跳过重建以免重置插入点/滚动。
        if context.coordinator.isAwaitingEditCommit {
            context.coordinator.isAwaitingEditCommit = false
            return
        }
        // 编辑中不触碰 textStorage，避免覆盖用户输入。
        guard !isEditable else { return }

        Self.applyContent(
            to: textView,
            attributedTextData: attributedTextData,
            plainText: plainText,
            font: font,
            showsFormatting: displaysFormatting
        )
        textView.scroll(.zero)
    }

    /// 视图移除时关闭 NSTextFinder：匹配高亮在独立窗口里，不关会一直残留。
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? NSTextView ?? coordinator.textView else {
            return
        }
        // 收回字体面板目标，避免改到已移除的视图。
        coordinator.stopObservingTextStorage()
        coordinator.releaseFontPanelTarget(for: textView)
        // 刻意不落盘：关闭预览即放弃编辑，落盘只走「完成」/Esc。
        dismissFindInterface(in: textView)
    }

    // MARK: - 查找栏

    /// 经 NSTextFinder 关闭查找界面；直接改 isFindBarVisible 会让浮层遮罩残留。
    /// 约定：查找栏显隐只由 NSTextFinder 掌管。
    static func dismissFindInterface(in textView: NSTextView) {
        let sender = NSMenuItem()
        sender.tag = NSTextFinder.Action.hideFindInterface.rawValue
        textView.performTextFinderAction(sender)
    }

    // MARK: - 文本视图与内容

    /// 构造预览文本视图：系统默认栈即 TextKit 2；不要读 layoutManager，否则永久回退 TextKit 1。
    /// 容器高度放开、宽度跟随视图。
    private static func makeTextView() -> PreviewTextView {
        let textView = PreviewTextView(frame: .zero)
        textView.textContainer?.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        return textView
    }

    /// 写入内容：可解码且显示格式时用 RTF，否则回退纯文本。
    private static func applyContent(
        to textView: NSTextView,
        attributedTextData: Data?,
        plainText: String?,
        font: NSFont,
        showsFormatting: Bool
    ) {
        let defaultFont = font
        if showsFormatting,
           let attributedTextData,
           let attributed = NSAttributedString(rtf: attributedTextData, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributed)
        } else {
            textView.textStorage?.setAttributedString(
                NSAttributedString(
                    string: plainText ?? "",
                    attributes: [
                        .font: defaultFont,
                        .foregroundColor: NSColor.textColor,
                    ]
                )
            )
        }
        textView.typingAttributes = [
            .font: defaultFont,
            .foregroundColor: NSColor.textColor,
        ]
        // 替换正文会把插入点挪到文末，钉回文首避免首屏停在末尾。
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    /// 内容独立快照：mutableCopy 脱离底层存储，避免后续编辑同步改动快照。
    fileprivate static func snapshot(of textView: NSTextView) -> NSAttributedString {
        guard let copy = textView.attributedString().mutableCopy() as? NSMutableAttributedString else {
            return NSAttributedString(string: textView.string)
        }
        return copy
    }

    // MARK: - 编辑与写回

    /// 进入编辑时把插入点落回可见区，避免输入时正文被拉回开头。
    /// characterIndexForInsertion 会强制布局，必须等 SwiftUI 更新事务结束再调用。
    private static func revealInsertionPointForEditing(in textView: NSTextView) {
        guard textView.selectedRange().length == 0 else { return }
        let visible = textView.visibleRect
        guard visible.height > 0 else { return }
        let x = textView.textContainerInset.width + 1
        let top = textView.characterIndexForInsertion(at: NSPoint(x: x, y: visible.minY + 2))
        let bottom = textView.characterIndexForInsertion(at: NSPoint(x: x, y: visible.maxY - 2))
        let caret = textView.selectedRange().location
        guard caret < top || caret > bottom else { return }
        textView.setSelectedRange(NSRange(location: top, length: 0))
    }

    /// 写回模型的 RTF；内容无格式时返回 nil，保持纯文本粘贴语义。
    /// 编码前剥掉系统文字色，避免深色外观下固化具体 RGB。
    static func rtfData(from content: NSAttributedString) -> Data? {
        let range = NSRange(location: 0, length: content.length)
        guard range.length > 0, !isPlainContent(content) else { return nil }

        let sanitized = NSMutableAttributedString(attributedString: content)
        let defaultTextColor = NSColor.textColor
        sanitized.enumerateAttribute(.foregroundColor, in: range, options: []) { value, attributeRange, _ in
            guard let color = value as? NSColor, color.isEqual(defaultTextColor) else { return }
            sanitized.removeAttribute(.foregroundColor, range: attributeRange)
        }
        return try? sanitized.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// 内容是否仍为纯文本；认不出时按有格式处理，宁多存不丢格式。
    private static func isPlainContent(_ content: NSAttributedString) -> Bool {
        let defaultFont = Self.defaultTextFont
        let defaultTextColor = NSColor.textColor
        var plain = true
        content.enumerateAttributes(in: NSRange(location: 0, length: content.length), options: []) { attributes, _, stop in
            for (key, value) in attributes {
                switch key {
                case .font:
                    plain = (value as? NSFont)?.isEqual(defaultFont) ?? false
                case .foregroundColor:
                    plain = (value as? NSColor)?.isEqual(defaultTextColor) ?? false
                default:
                    plain = false
                }
                if !plain {
                    stop.pointee = true
                    return
                }
            }
        }
        return plain
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        fileprivate weak var textView: PreviewTextView?
        var lastContentID: String?
        fileprivate var lastShowsFormatting = false
        var onEditingFinished: ((NSAttributedString) -> Void)?
        var onDirtyChange: ((Bool) -> Void)?
        private var textStorageObserver: NSObjectProtocol?
        var lastSaveRequestID = 0
        private var editingBaseline: NSAttributedString?
        /// 结果已交宿主保存，下一次内容变化无需重建。
        fileprivate var isAwaitingEditCommit = false
        /// 富文本编辑撤销栈，独立于搜索框 field editor。
        private let undoManager = UndoManager()

        /// ⌘S：保存当前正文并推进基线，编辑会话继续。
        /// 回调异步执行，避免在 SwiftUI 更新里改模型。
        func saveEditing(in textView: NSTextView) {
            guard let baseline = editingBaseline else { return }
            let current = TextPreviewView.snapshot(of: textView)
            guard !current.isEqual(to: baseline) else {
                // 无净变化：不写模型，只校正 dirty 标记。
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.reportDirty(in: textView)
                }
                return
            }
            editingBaseline = current
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.onEditingFinished?(current)
                if let textView {
                    // 回调期间可能又有输入，按最新基线重算 dirty。
                    self.reportDirty(in: textView)
                }
            }
        }

        private func reportDirty(in textView: NSTextView) {
            guard let baseline = editingBaseline else { return }
            onDirtyChange?(!TextPreviewView.snapshot(of: textView).isEqual(to: baseline))
        }

        /// 观察 textStorage 而非 textDidChange：直接改存储的路径也会通知。
        /// 通知里只在有编辑基线时比较，避免把程序化装填误报为用户改动。
        func observeTextStorage(of textView: NSTextView) {
            stopObservingTextStorage()
            guard let storage = textView.textStorage else { return }
            textStorageObserver = NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification,
                object: storage,
                queue: nil
            ) { [weak self, weak textView] _ in
                // 同步执行，保证输入后立刻 Esc 读到最新状态。
                guard Thread.isMainThread else { return }
                MainActor.assumeIsolated {
                    guard let self, let textView else { return }
                    self.reportDirty(in: textView)
                }
            }
        }

        func stopObservingTextStorage() {
            if let textStorageObserver {
                NotificationCenter.default.removeObserver(textStorageObserver)
            }
            textStorageObserver = nil
        }

        isolated deinit {
            if let textStorageObserver {
                NotificationCenter.default.removeObserver(textStorageObserver)
            }
        }

        /// 进入编辑：清空撤销栈并建立内容基线。
        func beginEditing(in textView: NSTextView) {
            undoManager.removeAllActions()
            editingBaseline = TextPreviewView.snapshot(of: textView)
            // 字体面板会抢走 key，显式把 target 指向正文，面板在前台时也能改字体。
            NSFontManager.shared.target = textView
        }

        func placeInsertionPointForEditing(in textView: NSTextView) {
            TextPreviewView.revealInsertionPointForEditing(in: textView)
        }

        /// 退出编辑：commit 且有净变化时保存；取消则恢复基线并清撤销栈。
        func finishEditing(in textView: NSTextView, commit: Bool) {
            let finished = TextPreviewView.snapshot(of: textView)
            let baseline = editingBaseline
            editingBaseline = nil
            releaseFontPanelTarget(for: textView)

            guard commit else {
                // 取消：必须恢复基线，否则只读预览会显示未保存内容；撤销栈一并清掉。
                if let baseline {
                    textView.textStorage?.setAttributedString(baseline)
                    textView.setSelectedRange(NSRange(location: 0, length: 0))
                }
                undoManager.removeAllActions()
                return
            }

            guard let onEditingFinished else { return }

            // 不能在视图更新中同步改状态，保存挪到下一轮主队列。
            isAwaitingEditCommit = true
            DispatchQueue.main.async { [weak self] in
                let changed = baseline.map { !finished.isEqual(to: $0) } ?? true
                guard changed else {
                    // 无净变化：不保存，也不跳过下次内容刷新。
                    self?.isAwaitingEditCommit = false
                    return
                }
                onEditingFinished(finished)
            }
        }

        fileprivate func releaseFontPanelTarget(for textView: NSTextView?) {
            guard let textView, NSFontManager.shared.target === textView else { return }
            NSFontManager.shared.target = nil
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        /// 链接不跳转，避免预览唤起浏览器抢焦点。
        func textView(
            _ textView: NSTextView,
            clickedOnLink link: Any,
            at charIndex: Int
        ) -> Bool {
            true
        }
    }
}
