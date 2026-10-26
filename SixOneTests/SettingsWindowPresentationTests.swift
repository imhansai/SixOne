//
//  SettingsWindowPresentationTests.swift
//  SixOneTests

import AppKit
import Testing
@testable import SixOne

@Suite("设置窗口回前台")
@MainActor
struct SettingsWindowPresentationTests {
    private final class ActivationSpy {
        private(set) var activations = 0
        private(set) var orderFronts = 0
        var isAppFrontmost = false

        var bringForward: WindowBringForward {
            WindowBringForward(
                isAppFrontmost: { [self] in isAppFrontmost },
                frontmostApplication: { NSRunningApplication.current },
                activate: { [self] _ in activations += 1 },
                orderFront: { [self] in orderFronts += 1 }
            )
        }
    }

    private func makeSettingsWindow() -> SettingsWindow {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.makeKeyAndOrderFront(nil)
        return window
    }

    @Test("系统设置退出、窗口还在、本应用不是前台：请回前台")
    func bringsWindowForwardWhenSystemSettingsQuits() {
        let spy = ActivationSpy()
        let presentation = SettingsWindowPresentation()
        presentation.bringForward = spy.bringForward
        let window = makeSettingsWindow()
        presentation.isWindowVisible = { [weak window] in window?.isVisible ?? false }
        defer { window.orderOut(nil) }

        presentation.systemSettingsDidTerminate(SettingsWindowPresentation.systemSettingsBundleIdentifier)

        #expect(spy.orderFronts == 1, "窗口应被前移")
        #expect(spy.activations == 1, "应请求一次激活")
    }

    @Test("窗口没显示：不动前台")
    func staysPutWhenSettingsWindowIsHidden() {
        let spy = ActivationSpy()
        let presentation = SettingsWindowPresentation()
        presentation.bringForward = spy.bringForward
        presentation.isWindowVisible = { false }

        presentation.systemSettingsDidTerminate(SettingsWindowPresentation.systemSettingsBundleIdentifier)

        #expect(spy.activations == 0)
    }

    @Test("退出的不是系统设置：不动前台")
    func ignoresOtherApplications() {
        let spy = ActivationSpy()
        let presentation = SettingsWindowPresentation()
        presentation.bringForward = spy.bringForward
        presentation.isWindowVisible = { true }

        presentation.systemSettingsDidTerminate("com.apple.finder")

        #expect(spy.activations == 0)
    }

    @Test("来源无法确认：不动前台")
    func ignoresUnknownTermination() {
        let spy = ActivationSpy()
        let presentation = SettingsWindowPresentation()
        presentation.bringForward = spy.bringForward
        presentation.isWindowVisible = { true }

        presentation.systemSettingsDidTerminate(nil)

        #expect(spy.activations == 0)
    }

    @Test("本应用已在前台：不重复请求激活")
    func skipsWhenAppAlreadyFrontmost() {
        let spy = ActivationSpy()
        spy.isAppFrontmost = true
        let presentation = SettingsWindowPresentation()
        presentation.bringForward = spy.bringForward
        presentation.isWindowVisible = { true }

        presentation.systemSettingsDidTerminate(SettingsWindowPresentation.systemSettingsBundleIdentifier)

        #expect(spy.activations == 0)
    }

    @Test("窗口显示期间只装一次观察者")
    func registersObserverOnlyOnce() {
        let presentation = SettingsWindowPresentation()
        presentation.isWindowVisible = { false }

        presentation.windowDidShow()
        presentation.windowDidShow()
        presentation.windowDidShow()

        #expect(presentation.isWatchingSystemSettings)
    }

    @Test("接线：控制器把设置窗口的显示状态接给了回前台判定")
    func controllerWiresWindowVisibility() throws {
        let controller = SettingsWindowController(
            settings: SettingsStore(storage: InMemorySettingsStorage()),
            hotKeyManager: HotKeyManager(onTrigger: {}, storage: InMemorySettingsStorage()),
            loadStorageStats: { HistoryStorageStats(itemCount: 0, byteCount: 0) },
            onClearHistory: {}
        )
        let window = try #require(controller.window as? SettingsWindow)
        defer { window.orderOut(nil) }

        #expect(!controller.presentation.isWindowVisible(), "窗口没显示时不该判定为可见")
        controller.showSettings()
        #expect(controller.presentation.isWindowVisible(), "显示之后判定应跟着窗口走")
    }
}
