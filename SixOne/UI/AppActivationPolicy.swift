//
//  AppActivationPolicy.swift
//  SixOne
//
//  常规应用身份按持有者登记；最后一个离场时恢复菜单栏应用。
//

import AppKit

@MainActor
protocol ActivationPolicyControlling: AnyObject {
    func beginRegular(_ holder: AnyObject)
    func endRegular(_ holder: AnyObject)
    func activateApp()
}

@MainActor
final class AppActivationPolicy: ActivationPolicyControlling {
    private let isEnabled: Bool
    private let currentPolicy: () -> NSApplication.ActivationPolicy
    private let setPolicy: (NSApplication.ActivationPolicy) -> Void
    private let activate: () -> Void
    private var regularHolders: Set<ObjectIdentifier> = []

    init(
        isEnabled: Bool = true,
        currentPolicy: @escaping () -> NSApplication.ActivationPolicy,
        setPolicy: @escaping (NSApplication.ActivationPolicy) -> Void,
        activate: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.currentPolicy = currentPolicy
        self.setPolicy = setPolicy
        self.activate = activate
    }

    convenience init(isEnabled: Bool = true, application: NSApplication = .shared) {
        self.init(
            isEnabled: isEnabled,
            currentPolicy: { application.activationPolicy() },
            setPolicy: { application.setActivationPolicy($0) },
            activate: {
                // 协作式激活：以当前前台应用为交出方，失败再回退。
                guard let frontmost = NSWorkspace.shared.frontmostApplication else {
                    application.activate()
                    return
                }
                guard frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                    return
                }
                if !NSRunningApplication.current.activate(from: frontmost, options: []) {
                    application.activate()
                }
            }
        )
    }

    func beginRegular(_ holder: AnyObject) {
        regularHolders.insert(ObjectIdentifier(holder))
        guard isEnabled else { return }
        // open / LaunchServices 可能先把 app 提成 regular；这里只负责身份，不抢激活。
        if currentPolicy() != .regular {
            setPolicy(.regular)
        }
    }

    /// 窗口先 `makeKeyAndOrderFront`，再从这里接回激活，避免激活把别的窗口顶上来。
    func activateApp() {
        guard isEnabled else { return }
        activate()
    }

    func endRegular(_ holder: AnyObject) {
        regularHolders.remove(ObjectIdentifier(holder))
        guard isEnabled, regularHolders.isEmpty else { return }
        setPolicy(.accessory)
    }
}
