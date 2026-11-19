//
//  CollectionEditor.swift
//  SixOne
//  新建 / 重命名用户分组：NSAlert + 单行文本框 + 内联校验。
//

import AppKit

@MainActor
enum CollectionEditor {
    static let sheetIdentifier = NSUserInterfaceItemIdentifier("SixOne.collectionEditor")
    static let counterIdentifier = NSUserInterfaceItemIdentifier("SixOne.collectionEditor.counter")

    private enum Metrics {
        static let width: CGFloat = 260
        static let counterWidth: CGFloat = 50
        static let gap: CGFloat = 4
        static var fieldWidth: CGFloat { width - counterWidth - gap }
        static var counterX: CGFloat { width - counterWidth }
    }

    enum Mode {
        case create
        case rename(currentName: String)

        var title: String {
            switch self {
            case .create: Localizer.string("New Group")
            case .rename: Localizer.string("Rename Group")
            }
        }

        var actionTitle: String {
            switch self {
            case .create: Localizer.string("Create")
            case .rename: Localizer.string("Rename")
            }
        }

        var initialName: String {
            switch self {
            case .create: ""
            case .rename(let currentName): currentName
            }
        }
    }

    /// - Parameter existingNames: 除当前分组外的已有分组名；用于内联重名提示。
    static func present(
        on window: NSWindow,
        mode: Mode,
        existingNames: [String],
        onSave: @escaping (String) -> Void,
        onClose: @escaping () -> Void = {}
    ) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = mode.title
        alert.window.identifier = Self.sheetIdentifier
        alert.addButton(withTitle: mode.actionTitle)
        alert.addButton(withTitle: Localizer.string("Cancel"))

        let field = NSTextField(string: mode.initialName)
        field.placeholderString = Localizer.string("Group Name")
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        // 字段右侧留出计数位；错误提示仍占一整行。
        field.frame = NSRect(x: 0, y: 24, width: Metrics.fieldWidth, height: 24)

        // 固定预留一行提示，避免出错时弹窗高度跳动。
        let message = NSTextField(labelWithString: "")
        message.textColor = .systemRed
        message.font = .systemFont(ofSize: 11)
        message.lineBreakMode = .byTruncatingTail
        message.frame = NSRect(x: 0, y: 0, width: Metrics.width, height: 16)

        // 字数指示器：`12 / 40`，到上限转橙。
        let counter = NSTextField(labelWithString: "")
        counter.identifier = Self.counterIdentifier
        counter.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        counter.textColor = .secondaryLabelColor
        counter.alignment = .right
        counter.frame = NSRect(
            x: Metrics.counterX,
            y: 28,
            width: Metrics.counterWidth,
            height: 16
        )
        counter.setAccessibilityLabel(Localizer.string("Character Count"))

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: 48))
        accessory.addSubview(field)
        accessory.addSubview(message)
        accessory.addSubview(counter)
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = field

        let coordinator = Coordinator(
            field: field,
            message: message,
            counter: counter,
            saveButton: alert.buttons.first,
            existingNames: existingNames,
            onSave: onSave
        )
        field.delegate = coordinator
        coordinator.refreshValidation()
        alert.beginSheetModal(for: window) { response in
            coordinator.handle(response)
            onClose()
        }

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }

    private final class Coordinator: NSObject, NSTextFieldDelegate {
        private let field: NSTextField
        private let message: NSTextField
        private let counter: NSTextField
        private let saveButton: NSButton?
        private let existingNames: [String]
        private let onSave: (String) -> Void
        /// 首次编辑后才显示「空名」提示；重名立即提示。
        private var hasEdited = false

        init(
            field: NSTextField,
            message: NSTextField,
            counter: NSTextField,
            saveButton: NSButton?,
            existingNames: [String],
            onSave: @escaping (String) -> Void
        ) {
            self.field = field
            self.message = message
            self.counter = counter
            self.saveButton = saveButton
            self.existingNames = existingNames
            self.onSave = onSave
        }

        func handle(_ response: NSApplication.ModalResponse) {
            guard response == .alertFirstButtonReturn,
                  case .valid(let name) = validation else { return }
            onSave(name)
        }

        private var validation: CollectionNameValidation {
            CollectionNameRules.validate(field.stringValue, among: existingNames)
        }

        func controlTextDidChange(_ obj: Notification) {
            hasEdited = true
            clampLength()
            // 输入法组合中不按未提交文本校验，否则会闪出假重名。
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
                return
            }
            refreshValidation()
        }

        /// 输入长度限制在名称上限内，保存时不再静默截断。
        private func clampLength() {
            guard let editor = field.currentEditor() as? NSTextView,
                  !editor.hasMarkedText() else { return }
            let value = field.stringValue
            guard value.count > CollectionNameNormalizer.maxLength else { return }
            field.stringValue = String(value.prefix(CollectionNameNormalizer.maxLength))
            editor.setSelectedRange(
                NSRange(location: field.stringValue.utf16.count, length: 0)
            )
        }

        /// 同步按钮、提示与字数。
        func refreshValidation() {
            updateCounter()
            let validation = validation
            saveButton?.isEnabled = validation.canSubmit
            if let text = messageText(for: validation), hasEdited || validation == .duplicate {
                message.stringValue = text
                message.isHidden = false
            } else {
                message.stringValue = ""
                message.isHidden = true
            }
        }

        private func updateCounter() {
            let count = field.stringValue.count
            let maxLength = CollectionNameNormalizer.maxLength
            counter.stringValue = String(
                format: Localizer.string("%lld / %lld"),
                count,
                maxLength
            )
            counter.textColor = count >= maxLength ? .systemOrange : .secondaryLabelColor
        }

        private func messageText(for validation: CollectionNameValidation) -> String? {
            switch validation {
            case .empty: Localizer.string("Group name cannot be empty.")
            case .duplicate: Localizer.string("A group with this name already exists.")
            case .valid: nil
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  !textView.hasMarkedText(),
                  let window = control.window,
                  let parent = window.sheetParent else { return false }
            guard validation.canSubmit else {
                hasEdited = true
                refreshValidation()
                NSSound.beep()
                return true
            }
            parent.endSheet(window, returnCode: .alertFirstButtonReturn)
            return true
        }
    }
}
