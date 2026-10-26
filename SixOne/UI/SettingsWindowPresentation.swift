//
//  SettingsWindowPresentation.swift
//  SixOne
//
//  系统设置退出后把设置窗口请回前台：LSUIElement 应用不会自动拿回激活。
//

import AppKit

@MainActor
struct WindowBringForward {
    /// 是否最前；读 WindowServer 状态，`NSApp.isActive` 会晚一拍。
    var isAppFrontmost: () -> Bool
    var frontmostApplication: () -> NSRunningApplication?
    var activate: (NSRunningApplication) -> Void
    /// 激活前先前移窗口，否则激活可能把别的窗口顶上来。
    var orderFront: () -> Void

    static let live = WindowBringForward(
        isAppFrontmost: {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        },
        frontmostApplication: { NSWorkspace.shared.frontmostApplication },
        activate: { from in
            // 协作式激活：以前台应用为交出方（未文档化，见 ClipboardPanelController）。
            NSRunningApplication.current.activate(from: from, options: [])
        },
        orderFront: {
            for window in NSApp.windows where window is SettingsWindow {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
    )

    func bringForward() {
        guard !isAppFrontmost() else { return }
        orderFront()
        guard let from = frontmostApplication() else { return }
        activate(from)
    }
}

/// 系统设置退出时请回前台；只在退出时动作，避免用户切应用时抢前台。
@MainActor
final class SettingsWindowPresentation {
    /// 设置窗口是否显示着；没有窗口就不动前台。
    var isWindowVisible: () -> Bool = { false }
    var bringForward = WindowBringForward.live

    /// 观察者只装一次。
    var isWatchingSystemSettings: Bool { !observers.isEmpty }
    private var observers: [NSObjectProtocol] = []

    func windowDidShow() {
        guard !isWatchingSystemSettings else { return }
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let terminated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    self?.systemSettingsDidTerminate(terminated?.bundleIdentifier)
                }
            }
        )
    }

    /// 退出的应用；`nil` 表示来源无法确认。
    func systemSettingsDidTerminate(_ terminatedBundleIdentifier: String?) {
        guard terminatedBundleIdentifier == Self.systemSettingsBundleIdentifier,
              isWindowVisible() else { return }
        bringForward.bringForward()
    }

    /// 深链里的 `com.apple.preference.security` 是面板标识，这里要的是应用标识。
    static let systemSettingsBundleIdentifier = "com.apple.systempreferences"
}
