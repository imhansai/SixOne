//
//  SettingsSidebarTests.swift
//  SixOneTests
//  设置侧栏：宽度范围、系统折叠按钮、折叠/展开与打开时的焦点归属。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("设置窗口侧栏")
@MainActor
struct SettingsSidebarTests {
    private static let waitTimeout: Duration = .seconds(10)

    private func makeHostedSettings() -> (navigation: SettingsNavigation, window: NSWindow) {
        let hosted = SettingsTestHost.make()
        hosted.window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        hosted.window.orderFrontRegardless()
        return hosted
    }

    private func splitViewController(in window: NSWindow) -> NSSplitViewController? {
        guard let content = window.contentView,
              let splitView = OffscreenHost.allSubviews(of: content)
                  .compactMap({ $0 as? NSSplitView }).first
        else { return nil }
        return splitView.delegate as? NSSplitViewController
    }

    /// NavigationSplitView 异步建出 NSSplitViewController，需轮询等待。
    private func waitForSplitViewController(in window: NSWindow) async throws -> NSSplitViewController {
        var controller: NSSplitViewController?
        let appeared = await Wait.until(timeout: Self.waitTimeout) {
            controller = splitViewController(in: window)
            return controller != nil
        }
        #expect(appeared, "设置窗口没有建出 NSSplitView")
        return try #require(controller)
    }

    private func sidebarTable(in item: NSSplitViewItem) -> NSTableView? {
        OffscreenHost.allSubviews(of: item.viewController.view)
            .compactMap { $0 as? NSTableView }
            .first
    }

    private func sidebarToggleItem(in window: NSWindow) -> NSToolbarItem? {
        window.toolbar?.items.first { $0.itemIdentifier.rawValue.hasSuffix("toggleSidebar") }
    }

    @Test("侧栏宽度限定在 180–200，且可折叠")
    func sidebarWidthRange() async throws {
        let (_, window) = makeHostedSettings()
        defer { window.orderOut(nil) }

        let controller = try await waitForSplitViewController(in: window)
        let item = try #require(controller.splitViewItems.first)

        #expect(item.minimumThickness == 180, "侧栏最小宽度应是 180")
        #expect(item.maximumThickness == 200, "侧栏最大宽度应是 200")
        #expect(item.canCollapse, "侧栏应可折叠，系统折叠按钮才可用")
    }

    @Test("系统折叠按钮常驻工具栏")
    func systemSidebarToggleStaysAvailable() async throws {
        let (navigation, window) = makeHostedSettings()
        defer { window.orderOut(nil) }

        _ = try await waitForSplitViewController(in: window)
        let expandedToggle = try #require(sidebarToggleItem(in: window), "工具栏应包含系统折叠按钮")
        #expect(expandedToggle.isVisible)

        navigation.columnVisibility = .detailOnly
        let collapsed = await Wait.until(timeout: Self.waitTimeout) {
            sidebarToggleItem(in: window)?.isVisible == true
        }
        #expect(collapsed, "侧栏收起后折叠按钮仍应可见，否则用户无法恢复")
    }

    @Test("侧栏可折叠，也能再次展开")
    func sidebarCollapsesAndExpands() async throws {
        let (navigation, window) = makeHostedSettings()
        defer { window.orderOut(nil) }

        let controller = try await waitForSplitViewController(in: window)
        let item = try #require(controller.splitViewItems.first)

        navigation.columnVisibility = .detailOnly
        let collapsed = await Wait.until(timeout: Self.waitTimeout) { item.isCollapsed }
        #expect(collapsed, "置为 detailOnly 后侧栏应收起")

        navigation.columnVisibility = .all
        let expanded = await Wait.until(timeout: Self.waitTimeout) { !item.isCollapsed }
        #expect(expanded, "置为 all 后侧栏应展开")
    }

    @Test("打开设置时焦点落在侧栏，重新请求后仍回到侧栏")
    func sidebarOwnsKeyboardFocus() async throws {
        let (navigation, window) = makeHostedSettings()
        defer { window.orderOut(nil) }

        let controller = try await waitForSplitViewController(in: window)
        let sidebar = try #require(controller.splitViewItems.first)
        let table = try #require(sidebarTable(in: sidebar), "侧栏列表没有出现")

        let initiallyFocused = await Wait.until(timeout: Self.waitTimeout) {
            window.firstResponder === table
        }
        #expect(initiallyFocused, "打开设置时焦点应落在侧栏列表")

        window.makeFirstResponder(nil)
        #expect(window.firstResponder === window, "测试前置：焦点应已离开侧栏")

        navigation.requestSidebarFocus()
        let focusedAgain = await Wait.until(timeout: Self.waitTimeout) {
            window.firstResponder === table
        }
        #expect(focusedAgain, "重新显示设置时焦点应回到侧栏列表")
    }

    @Test("控制器显示窗口时把焦点交给侧栏")
    func controllerShowsWithSidebarFocus() async throws {
        let controller = SettingsWindowController(
            settings: SettingsStore(storage: InMemorySettingsStorage()),
            hotKeyManager: HotKeyManager(onTrigger: {}, storage: InMemorySettingsStorage()),
            loadStorageStats: { HistoryStorageStats(itemCount: 0, byteCount: 0) },
            onClearHistory: {}
        )
        let window = try #require(controller.window)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        defer { window.orderOut(nil) }

        controller.showSettings()

        let splitController = try await waitForSplitViewController(in: window)
        let sidebar = try #require(splitController.splitViewItems.first)
        let table = try #require(sidebarTable(in: sidebar), "侧栏列表没有出现")
        let focused = await Wait.until(timeout: Self.waitTimeout) {
            window.firstResponder === table
        }
        #expect(focused, "showSettings 应通过导航模型把焦点交给侧栏")
    }

    @Test("控制器显示窗口时同步清掉详情区的初始焦点")
    func controllerClearsDetailInitialFocus() async throws {
        let controller = SettingsWindowController(
            settings: SettingsStore(storage: InMemorySettingsStorage()),
            hotKeyManager: HotKeyManager(onTrigger: {}, storage: InMemorySettingsStorage()),
            loadStorageStats: { HistoryStorageStats(itemCount: 0, byteCount: 0) },
            onClearHistory: {}
        )
        let window = try #require(controller.window)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        defer { window.orderOut(nil) }

        controller.showSettings()
        #expect(!(window.firstResponder is NSControl), "首次显示返回时焦点不应停在详情区控件上")

        let splitController = try await waitForSplitViewController(in: window)
        let detail = try #require(splitController.splitViewItems.dropFirst().first?.viewController.view)
        let control = try #require(
            OffscreenHost.allSubviews(of: detail)
                .compactMap { $0 as? NSControl }
                .first { $0.acceptsFirstResponder },
            "详情区没有可聚焦控件"
        )
        _ = await Wait.until(timeout: Self.waitTimeout) { window.firstResponder is NSTableView }
        #expect(window.makeFirstResponder(control), "测试前置：焦点应能落到详情区控件")
        #expect(window.firstResponder === control)

        controller.showSettings()

        // 清焦点在 showSettings 内；侧栏聚焦排在下一拍。
        #expect(window.firstResponder !== control, "showSettings 返回时不应把焦点留在详情区控件")
        #expect(window.firstResponder === window || window.firstResponder is NSTableView)

        let focused = await Wait.until(timeout: Self.waitTimeout) { window.firstResponder is NSTableView }
        #expect(focused, "清掉初始焦点后，侧栏应在下一拍接管")
    }

    @Test("折叠再展开后点侧栏行，列表重新获得焦点")
    func clickingRowAfterRevealRestoresSidebarFocus() async throws {
        let (navigation, window) = makeHostedSettings()
        defer { window.orderOut(nil) }

        let splitController = try await waitForSplitViewController(in: window)
        let sidebar = try #require(splitController.splitViewItems.first)
        let table = try #require(sidebarTable(in: sidebar), "侧栏列表没有出现")
        _ = await Wait.until(timeout: Self.waitTimeout) { window.firstResponder === table }

        navigation.columnVisibility = .detailOnly
        let collapsed = await Wait.until(timeout: Self.waitTimeout) { sidebar.isCollapsed }
        #expect(collapsed, "侧栏应收起")
        navigation.columnVisibility = .all
        let expanded = await Wait.until(timeout: Self.waitTimeout) { !sidebar.isCollapsed }
        #expect(expanded, "侧栏应展开")
        let lostFocus = await Wait.until(timeout: Self.waitTimeout) { window.firstResponder !== table }
        #expect(lostFocus, "展开后列表应先处于未聚焦状态")

        #expect(await Wait.until(timeout: Self.waitTimeout) {
            table.numberOfRows == SettingsSection.allCases.count
        }, "侧栏行没有落进表格")

        table.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)

        let focused = await Wait.until(timeout: Self.waitTimeout) { window.firstResponder === table }
        #expect(focused, "点击侧栏行后列表应重新成为第一响应者，高亮才会恢复活动样式")
        #expect(navigation.current == .shortcuts)
    }
}
