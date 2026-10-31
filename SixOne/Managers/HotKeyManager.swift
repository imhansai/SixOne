//
//  HotKeyManager.swift
//  SixOne

import AppKit
import Carbon.HIToolbox
import Observation
import os

struct HotKeyRegistration {
    let release: () -> Void
}

/// 全局快捷键的系统注册口；测试注入假实现来制造注册失败。
protocol HotKeyRegistering {
    /// 注册一组快捷键；handle 为 nil 表示失败，status 为系统状态码。
    func register(keyCode: UInt32, modifiers: UInt32) -> (handle: HotKeyRegistration?, status: OSStatus)
}

/// 生产实现：Carbon 注册型快捷键，无需辅助功能权限，沙盒可用。
struct SystemHotKeyRegistrar: HotKeyRegistering {
    func register(keyCode: UInt32, modifiers: UInt32) -> (handle: HotKeyRegistration?, status: OSStatus) {
        // 签名 "SOX1"、id 固定 1：应用只有一条全局快捷键。
        let hotKeyID = EventHotKeyID(signature: 0x534F5831, id: 1)
        var ref: EventHotKeyRef?
        // 独占注册，避免非独占注册「成功但收不到事件」。
        let options = OptionBits(kEventHotKeyExclusive)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), options, &ref
        )
        guard status == noErr, let ref else { return (nil, status) }
        return (HotKeyRegistration { UnregisterEventHotKey(ref) }, status)
    }
}

/// 全局快捷键：注册、修改、清除；失败只反映在 `isRegistered` 上。
@Observable
final class HotKeyManager {
    static let defaultKeyCode = HotKeySettings.defaultKeyCode
    static let defaultModifiers = HotKeySettings.defaultModifiers

    private let onTrigger: () -> Void
    private let registrar: HotKeyRegistering
    private let eventMonitor: HotKeyEventMonitoring
    private let preferences: Preferences
    private let systemHotKeys: () -> [SystemSymbolicHotKey]
    private let logger = AppLog.logger("HotKey")

    var displayString: String
    var isConfigured: Bool
    /// 快捷键当前是否真的挂在系统上：启动时注册失败（被占用）会留在 false。
    private(set) var isRegistered = false
    private var changeObservers: [() -> Void] = []

    private var registration: HotKeyRegistration?
    private var eventHandler: HotKeyEventMonitorRegistration?
    private var inputSourceObserver: NSObjectProtocol?
    private var keyCode: UInt32
    private var modifiers: UInt32

    var isActive: Bool { isConfigured && isRegistered }

    /// 订阅配置变化；闭包按约定持弱引用，随装配图同生共死。
    func observeChanges(_ handler: @escaping () -> Void) {
        changeObservers.append(handler)
    }

    /// registrar / eventMonitor / storage 可注入以便测试。
    init(
        onTrigger: @escaping () -> Void,
        registrar: HotKeyRegistering? = nil,
        eventMonitor: HotKeyEventMonitoring? = nil,
        storage: SettingsStorage = UserDefaults.standard,
        systemHotKeys: @escaping () -> [SystemSymbolicHotKey] = { SystemSymbolicHotKey.current() }
    ) {
        self.onTrigger = onTrigger
        self.registrar = registrar ?? SystemHotKeyRegistrar()
        self.eventMonitor = eventMonitor ?? CarbonHotKeyEventMonitor()
        self.preferences = Preferences(storage: storage)
        self.systemHotKeys = systemHotKeys
        let saved = self.preferences.hotKey
        keyCode = saved.keyCode
        modifiers = saved.modifiers
        isConfigured = saved.isConfigured
        displayString = saved.isConfigured
            ? Self.displayString(keyCode: saved.keyCode, modifiers: saved.modifiers)
             : Localizer.string("Set Shortcut")
        // 快捷键存的是物理 keyCode，显示名要随布局刷新。
        inputSourceObserver = NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshDisplayString()
            }
        }
    }

    isolated deinit {
        if let inputSourceObserver {
            NotificationCenter.default.removeObserver(inputSourceObserver)
        }
        unregister()
        eventHandler?.release()
    }

    /// 注册已保存的快捷键（启动时调用）；失败不弹提示，`isRegistered` 如实为 false。
    func reapply() {
        guard isConfigured else { return }
        if registration != nil { return }
        // 旧版本存的组合可能不合规则（如只按 ⌘），留在未注册态。
        guard Self.isAcceptable(carbonModifiers: modifiers) else {
            isRegistered = false
            return
        }
        guard !Self.isSystemReserved(
            keyCode: keyCode,
            modifiers: modifiers,
            in: systemHotKeys()
        ) else {
            isRegistered = false
            return
        }
        registerCurrent()
    }

    /// 注册一组快捷键；失败时旧快捷键保持可用，返回 false。
    @discardableResult
    func update(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        apply(keyCode: UInt32(keyCode), modifiers: Self.carbonModifiers(from: modifiers))
    }

    @discardableResult
    func restoreDefaults() -> Bool {
        apply(keyCode: UInt32(Self.defaultKeyCode), modifiers: Self.defaultModifiers)
    }

    /// 注册并持久化一组快捷键；注册失败时回滚到原配置并返回 false。
    private func apply(keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard Self.isAcceptable(carbonModifiers: modifiers) else { return false }
        guard !Self.isSystemReserved(
            keyCode: keyCode,
            modifiers: modifiers,
            in: systemHotKeys()
        ) else {
            return false
        }
        let oldKeyCode = self.keyCode
        let oldModifiers = self.modifiers
        let oldDisplayString = displayString
        unregister()
        self.keyCode = keyCode
        self.modifiers = modifiers
        displayString = Self.displayString(keyCode: keyCode, modifiers: modifiers)
        registerCurrent()
        guard isRegistered else {
            self.keyCode = oldKeyCode
            self.modifiers = oldModifiers
            displayString = oldDisplayString
            reapply()
            return false
        }
        isConfigured = true
        preferences.hotKey = HotKeySettings(
            isConfigured: true,
            keyCode: self.keyCode,
            modifiers: self.modifiers
        )
        notifyChanges()
        return true
    }

    func clear() {
        unregister()
        isConfigured = false
        displayString = Localizer.string("Set Shortcut")
        preferences.hotKey = HotKeySettings(
            isConfigured: false,
            keyCode: keyCode,
            modifiers: modifiers
        )
        notifyChanges()
    }

    @discardableResult
    private func registerCurrent() -> OSStatus {
        // 事件处理器是收按键的前置；停用态启动时没装，这里每次兜一次。
        installEventHandlerIfNeeded()
        let outcome = registrar.register(keyCode: keyCode, modifiers: modifiers)
        if let handle = outcome.handle {
            registration = handle
            isRegistered = true
        } else {
            registration = nil
            isRegistered = false
            logger.error(
                "注册全局快捷键失败（\(self.displayString, privacy: .public)）：OSStatus \(outcome.status)"
            )
        }
        return outcome.status
    }

    /// 状态栏菜单的 key equivalent；无法用单字符表达时返回 nil。
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard let key = KeyNameResolver.shared.keyEquivalent(for: keyCode) else { return nil }
        return (key, Self.modifierFlags(from: modifiers))
    }

    static func modifierFlags(from carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if carbonModifiers & ModifierMasks.cmd != 0 { result.insert(.command) }
        if carbonModifiers & ModifierMasks.shift != 0 { result.insert(.shift) }
        if carbonModifiers & ModifierMasks.option != 0 { result.insert(.option) }
        if carbonModifiers & ModifierMasks.control != 0 { result.insert(.control) }
        return result
    }

    static func carbonModifiers(from modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= ModifierMasks.cmd }
        if modifiers.contains(.shift) { result |= ModifierMasks.shift }
        if modifiers.contains(.option) { result |= ModifierMasks.option }
        if modifiers.contains(.control) { result |= ModifierMasks.control }
        return result
    }

    /// 产品规则：Command 必须再带一个其它修饰键，只按 ⌘ 会抢系统常用命令。
    static func isAcceptable(carbonModifiers: UInt32) -> Bool {
        let hasCommand = carbonModifiers & ModifierMasks.cmd != 0
        let hasOther = carbonModifiers
            & (ModifierMasks.control | ModifierMasks.option | ModifierMasks.shift) != 0
        return hasCommand && hasOther
    }

    private static func isSystemReserved(
        keyCode: UInt32,
        modifiers: UInt32,
        in hotKeys: [SystemSymbolicHotKey]
    ) -> Bool {
        hotKeys.contains { hotKey in
            hotKey.isEnabled
                && hotKey.keyCode == keyCode
                && hotKey.modifiers == modifiers
        }
    }

    /// 修饰键按 ⌃⌥⇧⌘ 排列；keyName 可注入，测试不受布局影响。
    static func displayString(
        keyCode: UInt32,
        modifiers: UInt32,
        keyName: (UInt32) -> String = { KeyNameResolver.shared.name(for: $0) }
    ) -> String {
        var result = ""
        if modifiers & ModifierMasks.control != 0 { result += "⌃" }
        if modifiers & ModifierMasks.option != 0 { result += "⌥" }
        if modifiers & ModifierMasks.shift != 0 { result += "⇧" }
        if modifiers & ModifierMasks.cmd != 0 { result += "⌘" }
        result += keyName(keyCode)
        return result
    }

    // MARK: - 内部

    private func unregister() {
        registration?.release()
        registration = nil
        isRegistered = false
    }

    private func notifyChanges() {
        for observer in changeObservers { observer() }
    }

    private func refreshDisplayString() {
        guard isConfigured else { return }
        let updated = Self.displayString(keyCode: keyCode, modifiers: modifiers)
        guard updated != displayString else { return }
        displayString = updated
        notifyChanges()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        let outcome = eventMonitor.install { [weak self] in
            self?.onTrigger()
        }
        guard let handler = outcome.registration else {
            logger.error("安装全局快捷键事件处理器失败：OSStatus \(outcome.status)")
            return
        }
        eventHandler = handler
    }
}
