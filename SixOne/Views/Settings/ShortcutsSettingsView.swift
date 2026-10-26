//
//  ShortcutsSettingsView.swift
//  SixOne
//
//  设置 → 快捷键：录制全局快捷键。
//

import AppKit
import SwiftUI

struct ShortcutsSettingsView: View {
    let hotKeyManager: HotKeyManager

    var body: some View {
        Section {
            HStack {
                Text("Open Clipboard Window")
                Spacer()
                ShortcutRecorder(
                    displayString: displaysShortcut
                        ? hotKeyManager.displayString
                        : Localizer.string("Set Shortcut"),
                    isConfigured: displaysShortcut,
                    onClear: {
                        hotKeyManager.clear()
                    },
                    onCapture: { event in
                        if ShortcutConflictChecker(menu: NSApp.mainMenu).conflictsWithMenu(event) {
                            return false
                        }
                        return hotKeyManager.update(
                            keyCode: event.keyCode,
                            modifiers: event.modifierFlags
                        )
                    }
                )
                .frame(width: 96, height: 26)
                .accessibilityLabel(Text("Open Clipboard Window"))
            }
        } header: {
            Text("Global Shortcut")
        } footer: {
            HStack {
                Spacer()
                Button("Restore Defaults") {
                    if !hotKeyManager.restoreDefaults() {
                        NSSound.beep()
                    }
                }
            }
        }
    }

    private var displaysShortcut: Bool {
        hotKeyManager.isActive
    }
}
