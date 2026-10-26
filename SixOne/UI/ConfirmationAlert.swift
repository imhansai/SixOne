//
//  ConfirmationAlert.swift
//  SixOne
//
//  原生 NSAlert 确认框的薄封装：只管文案、按钮与回调，布局和焦点交给系统。
//

import AppKit

@MainActor
enum ConfirmationAlert {
    /// 以 sheet 显示确认框；主操作先加即为默认按钮，Cancel 后加。
    static func present(
        on window: NSWindow,
        title: String,
        message: String,
        actionTitle: String,
        onAction: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message

        let action = alert.addButton(withTitle: actionTitle)
        action.hasDestructiveAction = true
        alert.addButton(withTitle: Localizer.string("Cancel"))

        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                onAction()
            } else {
                onCancel()
            }
        }
    }
}
