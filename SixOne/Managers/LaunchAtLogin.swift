//
//  LaunchAtLogin.swift
//  SixOne
//
//  开机自启；register() 只是请求，开关状态一律回读系统状态。
//

import AppKit
import Foundation
import Observation
import ServiceManagement
import os

enum LoginItemStatus: Equatable {
    case notRegistered
    case enabled
    /// 已注册，等用户在「系统设置 → 通用 → 登录项」里批准。
    case requiresApproval
    /// 系统找不到这个登录项（例如应用不在 /Applications）。
    case notFound

    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        case .notRegistered: self = .notRegistered
        // 未来新增状态按未注册处理。
        @unknown default: self = .notRegistered
        }
    }
}

protocol LoginItemRegistering {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openLoginItemsSettings()
}

struct SystemLoginItem: LoginItemRegistering {
    var status: LoginItemStatus { LoginItemStatus(SMAppService.mainApp.status) }

    func register() throws { try SMAppService.mainApp.register() }

    func unregister() throws { try SMAppService.mainApp.unregister() }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@Observable
final class LaunchAtLogin {
    private let service: LoginItemRegistering
    private let notificationCenter: NotificationCenter
    private var activationObserver: NSObjectProtocol?
    private let logger = AppLog.logger("LaunchAtLogin")

    /// 开关位置；待批准也算「开」。
    private(set) var isEnabled = false
    private(set) var needsApproval = false
    private(set) var failure: String?

    /// notificationCenter 可注入；测试用独立中心。
    init(
        service: LoginItemRegistering = SystemLoginItem(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.service = service
        self.notificationCenter = notificationCenter
        // 回到前台回读一次，用户可能刚在系统设置里改过。
        activationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        refresh()
    }

    isolated deinit {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
    }

    func refresh() {
        switch service.status {
        case .enabled:
            isEnabled = true
            needsApproval = false
        case .requiresApproval:
            isEnabled = true
            needsApproval = true
        case .notRegistered, .notFound:
            isEnabled = false
            needsApproval = false
        }
    }

    /// 切换开关并回读真实状态；底层错误只进日志。
    func setEnabled(_ enabled: Bool) {
        failure = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            logger.error("切换开机自启失败（enabled=\(enabled, privacy: .public)）：\(error.localizedDescription, privacy: .public)")
            failure = Localizer.string("Couldn’t change the launch-at-login setting.")
        }
        refresh()
    }

    func openLoginItemsSettings() {
        service.openLoginItemsSettings()
    }
}
