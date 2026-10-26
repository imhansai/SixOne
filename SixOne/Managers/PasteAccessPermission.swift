//
//  PasteAccessPermission.swift
//  SixOne

import AppKit
import ApplicationServices
import IOKit.hid
import Observation

/// 管理「把 ⌘V 投递到其他应用」所需的辅助功能授权。
/// 授权查询可能被进程缓存，因此同时读多个信号，并在申请后用真实事件 tap 探测。
@Observable
final class PasteAccessPermission {
    static let shared = PasteAccessPermission()

    private(set) var isAuthorized = false

    private var hasRequestedAuthorization = false

    private var activationObserver: NSObjectProtocol?

    private init() {
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    isolated deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func refresh() {
        isAuthorized = CGPreflightPostEventAccess()
            || IOHIDCheckAccess(kIOHIDRequestTypePostEvent).rawValue == kIOHIDAccessTypeGranted.rawValue
            || AXIsProcessTrusted()
        // 查询可能返回旧值；申请后用事件 tap 直连 TCC 探测。
        if !isAuthorized, hasRequestedAuthorization {
            isAuthorized = canCreateModifyingEventTap()
        }
    }

    /// 粘贴前调用：已授权放行；首次未授权发起申请，本次不投递。
    @discardableResult
    func ensureGranted() -> Bool {
        refresh()
        if isAuthorized { return true }
        if !hasRequestedAuthorization {
            requestSystemAuthorization()
        }
        return false
    }

    func request() {
        refresh()
        guard !isAuthorized else { return }
        if hasRequestedAuthorization {
            openSystemSettings()
        } else {
            requestSystemAuthorization()
        }
    }

    func openSystemSettings() {
        hasRequestedAuthorization = true
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    private func canCreateModifyingEventTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }
        CFMachPortInvalidate(tap)
        return true
    }

    private func requestSystemAuthorization() {
        hasRequestedAuthorization = true
        CGRequestPostEventAccess()
        // 稍后刷新，让实时探测尽快反映授权结果。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
        }
    }
}
