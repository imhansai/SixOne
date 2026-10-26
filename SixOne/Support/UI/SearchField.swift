//
//  SearchField.swift
//  SixOne
//  面板顶栏原生搜索框：无放大镜、清除按钮、边框与背景。

import AppKit
import SwiftUI

extension NSUserInterfaceItemIdentifier {
    static let groupFilterField = NSUserInterfaceItemIdentifier("SixOne.groupFilterField")
}

/// 用 NSTextField 而非 NSSearchField：放大镜与清除按钮无法关闭，隐藏又会改坏编辑几何。
/// 文本与焦点由 delegate 和 focus/blurRequestID 驱动，不走 SwiftUI FocusState。
struct SearchField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let focusRequestID: Int
    let blurRequestID: Int
    var fontSize: CGFloat = 24
    var identifier: NSUserInterfaceItemIdentifier?
    /// 首次挂载即聚焦；按需重建的搜索框可能错过 `focusRequestID`。
    var focusOnAppear = false
    var onTextChange: (String) -> Void = { _ in }
    var onFocusChange: (Bool) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onTab: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusAwareTextField()
        field.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.reportFocus(focused)
        }
        // 先换 cell 再配字段：字段级设置会转发给 cell。
        field.cell = BorderlessBezelTextFieldCell()
        // isBordered 会取消 isBezeled，故先关 border、最后开 bezel。
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        if let cell = field.cell as? NSTextFieldCell {
            cell.usesSingleLineMode = true
            cell.wraps = false
            cell.lineBreakMode = .byClipping
            // 默认不可滚动会让长文本光标钉在右缘；打开后视口随插入点右移。
            cell.isScrollable = true
        }
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchFieldAction(_:))
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        field.identifier = identifier
        field.font = .systemFont(ofSize: fontSize)
        field.focusRingType = .none

        context.coordinator.searchField = field
        context.coordinator.updateCallbacks(
            onTextChange: onTextChange,
            onFocusChange: onFocusChange,
            onCancel: onCancel,
            onMoveDown: onMoveDown,
            onTab: onTab
        )
        context.coordinator.lastSyncedText = text
        context.coordinator.lastFocusRequestID = focusRequestID
        context.coordinator.lastBlurRequestID = blurRequestID
        field.stringValue = text
        if focusOnAppear {
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator, let field = coordinator.searchField,
                      let window = field.window else { return }
                if window.firstResponder !== field.currentEditor() {
                    window.makeFirstResponder(field)
                }
                coordinator.reportFocus(true)
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.searchField = field
        coordinator.updateCallbacks(
            onTextChange: onTextChange,
            onFocusChange: onFocusChange,
            onCancel: onCancel,
            onMoveDown: onMoveDown,
            onTab: onTab
        )

        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
            field.setAccessibilityLabel(placeholder)
        }
        if field.identifier != identifier {
            field.identifier = identifier
        }
        if field.font?.pointSize != fontSize {
            field.font = .systemFont(ofSize: fontSize)
        }

        // 同步程序化变更（Esc 清空/重置等）；输入法组合中不打断 marked text。
        let composing = (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        if !composing, field.stringValue != text {
            coordinator.lastSyncedText = text
            field.stringValue = text
            if let editor = field.currentEditor() {
                let end = (text as NSString).length
                editor.selectedRange = NSRange(location: end, length: 0)
            }
        }

        if focusRequestID != coordinator.lastFocusRequestID {
            coordinator.lastFocusRequestID = focusRequestID
            // 异步切第一响应者并上报，避免同步改状态触发 AttributeGraph cycle。
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator, let field = coordinator.searchField,
                      let window = field.window else { return }
                if window.firstResponder !== field.currentEditor() {
                    window.makeFirstResponder(field)
                }
                coordinator.reportFocus(true)
            }
        }
        if blurRequestID != coordinator.lastBlurRequestID {
            coordinator.lastBlurRequestID = blurRequestID
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator, let field = coordinator.searchField,
                      let window = field.window else { return }
                if window.firstResponder === field.currentEditor()
                    || window.firstResponder === field {
                    window.makeFirstResponder(nil)
                    coordinator.reportFocus(false)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        weak var searchField: NSTextField?
        private var onTextChange: (String) -> Void = { _ in }
        private var onFocusChange: (Bool) -> Void = { _ in }
        private var onCancel: () -> Void = {}
        private var onMoveDown: () -> Void = {}
        private var onTab: (Bool) -> Void = { _ in }
        var lastSyncedText = ""
        var lastFocusRequestID: Int?
        var lastBlurRequestID: Int?

        func updateCallbacks(
            onTextChange: @escaping (String) -> Void,
            onFocusChange: @escaping (Bool) -> Void,
            onCancel: @escaping () -> Void,
            onMoveDown: @escaping () -> Void,
            onTab: @escaping (Bool) -> Void
        ) {
            self.onTextChange = onTextChange
            self.onFocusChange = onFocusChange
            self.onCancel = onCancel
            self.onMoveDown = onMoveDown
            self.onTab = onTab
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            sync(field)
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            reportFocus(true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            reportFocus(false)
        }

        /// 字段编辑器把 Esc / ↓ / Return / Tab 转成标准命令后，先给面板一次机会。
        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel()
                return true
            case #selector(NSResponder.moveDown(_:)):
                onMoveDown()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                return true
            case #selector(NSResponder.insertTab(_:)):
                onTab(false)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                onTab(true)
                return true
            default:
                return false
            }
        }

        @objc func searchFieldAction(_ sender: NSTextField) {
            sync(sender)
        }

        fileprivate func reportFocus(_ focused: Bool) {
            onFocusChange(focused)
        }

        private func sync(_ field: NSTextField) {
            // 输入法组合中不推送中间 marked text，避免拼音候选反复触发搜索。
            if (field.currentEditor() as? NSTextView)?.hasMarkedText() == true {
                return
            }
            let value = field.stringValue
            guard value != lastSyncedText else { return }
            lastSyncedText = value
            onTextChange(value)
            if let editor = field.currentEditor() as? NSTextView {
                editor.scrollRangeToVisible(editor.selectedRange())
            }
        }
    }
}

/// 以 `currentEditor()` 判定真实编辑焦点；controlTextDidBeginEditing 会漏掉点击聚焦。
final class FocusAwareTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?

    var presentContextMenu: ((NSEvent) -> Void)?

    override func becomeFirstResponder() -> Bool {
        return super.becomeFirstResponder()
    }

    /// 右击会绕过 become/resign，需主动设置焦点，否则 SwiftUI 仍以为列表聚焦。
    override func rightMouseDown(with event: NSEvent) {
        focusForContextMenu()
        if let presentContextMenu {
            presentContextMenu(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    /// ⌃+左键与右键同义，但走 mouseDown。
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            focusForContextMenu()
        }
        super.mouseDown(with: event)
    }

    /// 已编辑时不重复切换，只补上报。
    func focusForContextMenu() {
        guard let window else { return }
        if currentEditor() == nil {
            window.makeFirstResponder(self)
        }
        if currentEditor() != nil {
            onFocusChange?(true)
        }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        guard resigned else { return false }
        if currentEditor() != nil {
            onFocusChange?(true)
        } else {
            // 延后一拍复核，兜住点击聚焦时序，也避免失焦误报。
            let field = self
            DispatchQueue.main.async { [weak field] in
                guard let field else { return }
                let editor = field.currentEditor()
                let focused = (editor != nil) && (field.window?.firstResponder === editor)
                field.onFocusChange?(focused)
            }
        }
        return true
    }
}

/// 保留 bezel 几何、只不画边框：文字区与 field editor clip 都依赖它。
private final class BorderlessBezelTextFieldCell: NSTextFieldCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawInterior(withFrame: cellFrame, in: controlView)
    }
}
