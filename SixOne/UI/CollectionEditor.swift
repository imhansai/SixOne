//
//  CollectionEditor.swift
//  SixOne
//  新建用户分组：NSAlert + 单行文本框。
//

import AppKit

@MainActor
enum CollectionEditor {
    static let sheetIdentifier = NSUserInterfaceItemIdentifier("SixOne.collectionEditor")

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

    static func present(
        on window: NSWindow,
        mode: Mode,
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
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let coordinator = Coordinator(field: field, onSave: onSave)
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
        private let onSave: (String) -> Void

        init(field: NSTextField, onSave: @escaping (String) -> Void) {
            self.field = field
            self.onSave = onSave
        }

        func handle(_ response: NSApplication.ModalResponse) {
            guard response == .alertFirstButtonReturn else { return }
            onSave(field.stringValue)
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
