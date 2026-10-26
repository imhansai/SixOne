//
//  ShortcutRecorder.swift
//  SixOne
//  快捷键录制控件：录制态只改显示；无修饰键只提示，失败留在录制态。

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let displayString: String
    let isConfigured: Bool
    let onClear: () -> Void
    let onCapture: (NSEvent) -> Bool

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = onCapture
        view.onClear = onClear
        view.setConfigured(isConfigured)
        view.setDisplayString(displayString)
        view.refreshLocalization()
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onCapture = onCapture
        view.onClear = onClear
        view.setConfigured(isConfigured)
        view.setDisplayString(displayString)
        view.refreshLocalization()
    }

    final class RecorderView: NSView {
        private enum Metrics {
            static let horizontalPadding: CGFloat = 8
            static let buttonTrailing: CGFloat = 5
            static let buttonSize: CGFloat = 18
            static let buttonSpacing: CGFloat = 2
            static let labelTrailingWithoutButton = -horizontalPadding
            static let labelTrailingWithButton = -(buttonTrailing + buttonSize + buttonSpacing)
        }

        var onCapture: ((NSEvent) -> Bool)?
        var onClear: (() -> Void)?
        private let label = NSTextField(labelWithString: "")
        private let clearButton = NSButton()
        private var isRecording = false
        private var configuredDisplayString = ""
        private var isConfigured = false
        private var labelTrailing: NSLayoutConstraint!

        override var acceptsFirstResponder: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityHelp(Localizer.string("Press to record a shortcut."))
            label.alignment = .center
            label.font = .systemFont(ofSize: 12)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            clearButton.title = ""
            clearButton.isBordered = false
            clearButton.image = NSImage(
                systemSymbolName: "xmark",
                accessibilityDescription: Localizer.string("Clear Shortcut")
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            )
            clearButton.contentTintColor = .secondaryLabelColor
            clearButton.target = self
            clearButton.action = #selector(clearShortcut)
            clearButton.toolTip = Localizer.string("Clear Shortcut")
            clearButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(clearButton)
            labelTrailing = label.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: Metrics.labelTrailingWithoutButton
            )
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                labelTrailing,
                clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.buttonTrailing),
                clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                clearButton.widthAnchor.constraint(equalToConstant: Metrics.buttonSize),
                clearButton.heightAnchor.constraint(equalToConstant: Metrics.buttonSize)
            ])
            setDisplayString("")
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func refreshLocalization() {
            setAccessibilityHelp(Localizer.string("Press to record a shortcut."))
            clearButton.toolTip = Localizer.string("Clear Shortcut")
            clearButton.image = NSImage(
                systemSymbolName: "xmark",
                accessibilityDescription: Localizer.string("Clear Shortcut")
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            )
        }

        func setDisplayString(_ string: String) {
            configuredDisplayString = string
            render()
        }

        func setConfigured(_ configured: Bool) {
            isConfigured = configured
            render()
        }

        private func render() {
            guard !isRecording else { return }
            label.stringValue = configuredDisplayString
            label.textColor = .labelColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.cornerRadius = 5
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.separatorColor.cgColor
            setAccessibilityValue(configuredDisplayString)
            updateClearButtonVisibility()
        }

        private func updateClearButtonVisibility() {
            let shouldShow = isConfigured && !isRecording
            clearButton.isHidden = !shouldShow
            clearButton.isEnabled = shouldShow
            labelTrailing.constant = shouldShow
                ? Metrics.labelTrailingWithButton
                : Metrics.labelTrailingWithoutButton
        }

        private func beginRecording() {
            guard !isRecording else { return }
            isRecording = true
            label.stringValue = Localizer.string("Press Shortcut…")
            label.textColor = .secondaryLabelColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            setAccessibilityValue(label.stringValue)
            updateClearButtonVisibility()
            window?.makeFirstResponder(self)
        }

        private func endRecording() {
            isRecording = false
            render()
        }

        override func mouseDown(with event: NSEvent) {
            beginRecording()
        }

        override func accessibilityPerformPress() -> Bool {
            guard !isRecording else { return true }
            beginRecording()
            return true
        }

        override func keyDown(with event: NSEvent) {
            // 非录制态的 Space/Return 也用来进入录制：键盘-only 用户不该只能靠鼠标。
            if !isRecording,
               event.keyCode == UInt16(kVK_Space) || event.keyCode == UInt16(kVK_Return) {
                beginRecording()
                return
            }
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            capture(event)
        }

        /// 录制态也捕获键等价事件；⌘W 等会在 keyDown 前被菜单截走。
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording else {
                return super.performKeyEquivalent(with: event)
            }
            capture(event)
            return true
        }

        private func capture(_ event: NSEvent) {
            if event.keyCode == UInt16(kVK_Escape) {
                endRecording()
                window?.makeFirstResponder(nil)
                return
            }
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !modifiers.isEmpty else {
                NSSound.beep()
                return
            }
            // 冲突预检需要 charactersIgnoringModifiers 对齐菜单 key equivalent。
            guard onCapture?(event) == true else {
                NSSound.beep()
                return
            }
            isRecording = false
            // 先用旧值顶一帧，等 SwiftUI 同步新组合。
            render()
            window?.makeFirstResponder(nil)
        }

        @objc private func clearShortcut() {
            guard !isRecording, clearButton.isEnabled else { return }
            onClear?()
        }

        override func resignFirstResponder() -> Bool {
            endRecording()
            return super.resignFirstResponder()
        }
    }
}
