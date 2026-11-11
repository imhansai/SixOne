//
//  AliasEditor.swift
//  SixOne
//  别名输入弹窗：NSAlert + 单行文本框，保存走归一化，清空即移除。
//

import AppKit

@MainActor
enum AliasEditor {
    static let sheetIdentifier = NSUserInterfaceItemIdentifier("SixOne.aliasEditor")

    /// 以 sheet 显示；`onSave` 只在保存或移除时调用，`onClose` 关闭时总会执行。
    static func present(
        on window: NSWindow,
        currentAlias: String?,
        onSave: @escaping (String?) -> Void,
        onClose: @escaping () -> Void
    ) {
        let hasAlias = AliasNormalizer.displayable(currentAlias) != nil

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = Localizer.string(hasAlias ? "Edit Alias" : "Add Alias")
        alert.informativeText = String(
            format: Localizer.string(
                "The alias replaces the title, can be found with search, and is limited to %@ characters."
            ),
            String(AliasNormalizer.maxLength)
        )
        alert.window.identifier = Self.sheetIdentifier
        alert.addButton(withTitle: Localizer.string("Save"))
        if hasAlias {
            let remove = alert.addButton(withTitle: Localizer.string("Remove Alias"))
            remove.hasDestructiveAction = true
        }
        alert.addButton(withTitle: Localizer.string("Cancel"))

        let field = NSTextField(string: currentAlias ?? "")
        field.placeholderString = Localizer.string("Alias")
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let coordinator = Coordinator(field: field, hasAlias: hasAlias, onSave: onSave)
        field.delegate = coordinator
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
        private let hasAlias: Bool
        private let onSave: (String?) -> Void

        init(field: NSTextField, hasAlias: Bool, onSave: @escaping (String?) -> Void) {
            self.field = field
            self.hasAlias = hasAlias
            self.onSave = onSave
        }

        func handle(_ response: NSApplication.ModalResponse) {
            switch response {
            case .alertFirstButtonReturn:
                onSave(ClipboardItem.normalizedAlias(field.stringValue))
            case .alertSecondButtonReturn where hasAlias:
                onSave(nil)
            default:
                break
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
            parent.endSheet(window, returnCode: .alertFirstButtonReturn)
            return true
        }
    }
}
