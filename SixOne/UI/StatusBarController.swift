//
//  StatusBarController.swift
//  SixOne
//

import AppKit

/// 菜单栏状态项：左键开关面板，右键弹菜单。
/// 激活走未文档化的 `NSRunningApplication.activate(from:)`；`NSApp.activate()` 不被批准。
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onToggleClipboard: () -> Void
    private let onOpenClipboard: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenAbout: () -> Void
    private let hotKeyManager: HotKeyManager

    private let menu = NSMenu()
    private let openClipboardItem: NSMenuItem
    private let settingsItem: NSMenuItem
    private let aboutItem: NSMenuItem
    private let quitItem: NSMenuItem
    private var isShowingMenu = false

    init(
        onToggleClipboard: @escaping () -> Void,
        onOpenClipboard: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void,
        hotKeyManager: HotKeyManager
    ) {
        self.onToggleClipboard = onToggleClipboard
        self.onOpenClipboard = onOpenClipboard
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        self.hotKeyManager = hotKeyManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.openClipboardItem = NSMenuItem(title: Localizer.string("Open Clipboard"), action: nil, keyEquivalent: "")
        self.settingsItem = NSMenuItem(title: Localizer.string("Settings"), action: #selector(openSettings), keyEquivalent: ",")
        self.aboutItem = NSMenuItem(title: Localizer.string("About SixOne"), action: #selector(openAbout), keyEquivalent: "")
        self.quitItem = NSMenuItem(title: Localizer.string("Quit SixOne"), action: #selector(quit), keyEquivalent: "q")
        super.init()
        configureButton()
        buildMenu()
        hotKeyManager.observeChanges { [weak self] in
            self?.updateOpenClipboardShortcut()
        }
        updateOpenClipboardShortcut()
    }

    var statusButtonScreenRect: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let rectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    /// 同步快捷键显示：优先菜单原生 key equivalent，只提示真正注册上的组合。
    func updateOpenClipboardShortcut() {
        let title = Localizer.string("Open Clipboard")
        guard hotKeyManager.isActive else {
            openClipboardItem.title = title
            openClipboardItem.keyEquivalent = ""
            openClipboardItem.keyEquivalentModifierMask = []
            return
        }
        if let equivalent = hotKeyManager.menuKeyEquivalent {
            openClipboardItem.title = title
            openClipboardItem.keyEquivalent = equivalent.key
            openClipboardItem.keyEquivalentModifierMask = equivalent.modifiers
        } else {
            openClipboardItem.title = title + "  \(hotKeyManager.displayString)"
            openClipboardItem.keyEquivalent = ""
            openClipboardItem.keyEquivalentModifierMask = []
        }
    }

    // MARK: - 私有

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        applyButtonLocalization()
    }

    private func applyButtonLocalization() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: Localizer.string("Clipboard History"))
        image?.isTemplate = true
        button.image = image
        button.toolTip = Localizer.string("Clipboard History")
    }

    private func buildMenu() {
        openClipboardItem.target = self
        openClipboardItem.action = #selector(openClipboard)
        menu.addItem(openClipboardItem)

        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard !isShowingMenu else { return }
        guard isSecondaryClick else {
            onToggleClipboard()
            return
        }
        isShowingMenu = true
        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
        isShowingMenu = false
    }

    private var isSecondaryClick: Bool {
        // 位掩码：1 << 1 为右键（按住中）。
        if NSEvent.pressedMouseButtons & 0x2 != 0 { return true }
        guard let event = NSApp.currentEvent else { return false }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return true
        case .leftMouseDown, .leftMouseUp:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }

    @objc private func openClipboard() {
        onOpenClipboard()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func openAbout() {
        onOpenAbout()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
