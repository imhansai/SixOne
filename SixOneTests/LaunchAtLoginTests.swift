//
//  LaunchAtLoginTests.swift
//  SixOneTests
//  登录项状态机：register() 只是请求，可能停在待批准，界面不得谎报已生效。

import AppKit
import Foundation
import Testing
@testable import SixOne

@MainActor
final class FakeLoginItem: LoginItemRegistering {
    var status: LoginItemStatus
    var statusAfterRegister: LoginItemStatus = .enabled
    var registerError: Error?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var didOpenLoginItems = false

    init(status: LoginItemStatus = .notRegistered) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCount += 1
        status = .notRegistered
    }

    func openLoginItemsSettings() {
        didOpenLoginItems = true
    }
}

@Suite("开机自启")
@MainActor
struct LaunchAtLoginTests {
    @Test("已注册但等用户批准：开关仍算「开」，并给出提示")
    func requiresApprovalKeepsSwitchOn() {
        let model = LaunchAtLogin(service: FakeLoginItem(status: .requiresApproval))

        #expect(model.isEnabled)
        #expect(model.needsApproval)
        #expect(model.failure == nil)
    }

    @Test("注册没抛错但系统只到「待批准」：不谎报已生效")
    func registerLandingInRequiresApproval() {
        let service = FakeLoginItem()
        service.statusAfterRegister = .requiresApproval
        let model = LaunchAtLogin(service: service)

        model.setEnabled(true)

        #expect(service.registerCount == 1)
        #expect(model.isEnabled)
        #expect(model.needsApproval, "要提示用户去系统设置里批准")
    }

    @Test("注册抛错：回到系统真实状态并说明原因")
    func registerFailureReports() {
        let service = FakeLoginItem()
        service.registerError = NSError(domain: "test", code: 1)
        let model = LaunchAtLogin(service: service)

        model.setEnabled(true)

        #expect(!model.isEnabled, "没注册成功，开关不该停在开")
        #expect(model.failure != nil)
        #expect(!model.needsApproval)
    }

    @Test("关掉：注销并落到关")
    func disableUnregisters() {
        let service = FakeLoginItem(status: .enabled)
        let model = LaunchAtLogin(service: service)
        #expect(model.isEnabled)

        model.setEnabled(false)

        #expect(service.unregisterCount == 1)
        #expect(!model.isEnabled)
    }

    @Test("系统里找不到这个登录项：开关落到关")
    func notFoundMeansOff() {
        let model = LaunchAtLogin(service: FakeLoginItem(status: .notFound))
        #expect(!model.isEnabled)
        #expect(!model.needsApproval)
    }

    @Test("刷新：状态在别处改了，这里跟着走")
    func refreshFollowsSystem() {
        let service = FakeLoginItem()
        let model = LaunchAtLogin(service: service)
        #expect(!model.isEnabled)

        service.status = .requiresApproval
        model.refresh()

        #expect(model.isEnabled)
        #expect(model.needsApproval)
    }

    @Test("打开登录项设置：交给系统")
    func opensLoginItemsSettings() {
        let service = FakeLoginItem()
        let model = LaunchAtLogin(service: service)

        model.openLoginItemsSettings()

        #expect(service.didOpenLoginItems)
    }

    @Test("回到前台：回读系统状态，用户在系统设置里批准后提示随之消失")
    func refreshesOnActivation() {
        // 用独立通知中心，不依赖真实系统通知。
        let center = NotificationCenter()
        let service = FakeLoginItem(status: .requiresApproval)
        let model = LaunchAtLogin(service: service, notificationCenter: center)
        #expect(model.isEnabled)
        #expect(model.needsApproval)

        service.status = .enabled
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(model.isEnabled)
        #expect(!model.needsApproval, "批准后横幅要消失，不能等用户切走再切回这一页")
    }
}
