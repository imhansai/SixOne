//
//  PanelWindowEventMonitor.swift
//  SixOne
//
//  面板窗口级监听：resign / becomeKey / becomeActive 与面板外点击。
//

import AppKit

final class PanelWindowEventMonitor {
    private let panel: ClipboardPanel
    private let onResignKey: () -> Void
    private let onBecomeKey: () -> Void
    private let onBecomeActive: () -> Void

    private var mouseMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var becomeKeyObserver: NSObjectProtocol?
    private var becomeActiveObserver: NSObjectProtocol?

    init(
        panel: ClipboardPanel,
        onResignKey: @escaping () -> Void,
        onBecomeKey: @escaping () -> Void,
        onBecomeActive: @escaping () -> Void
    ) {
        self.panel = panel
        self.onResignKey = onResignKey
        self.onBecomeKey = onBecomeKey
        self.onBecomeActive = onBecomeActive

        // 失去 key 时延后判定收起：resign 到达时新 key 窗口可能还没挂上。
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onResignKey()
            }
        }

        // 拿到 key 就激活应用：nonactivating 面板光成为 key 不会回到前台，手势只派给激活应用。
        becomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onBecomeKey()
            }
        }

        // 应用回到前台：停在「选服务」的分享会话已结束；执行中的服务由自身回话。
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onBecomeActive()
            }
        }
    }

    isolated deinit {
        removeAll()
    }

    /// 点面板外只是线索，真正是否收起交给焦点判定。
    func startOutsideClickMonitor(_ handler: @escaping () -> Void) {
        stopOutsideClickMonitor()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            guard !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            handler()
        }
    }

    func stopOutsideClickMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
    }

    /// 退订全部监听；可重复调用。
    func removeAll() {
        stopOutsideClickMonitor()
        for token in [resignObserver, becomeKeyObserver, becomeActiveObserver] {
            if let token {
                NotificationCenter.default.removeObserver(token)
            }
        }
        resignObserver = nil
        becomeKeyObserver = nil
        becomeActiveObserver = nil
    }
}
