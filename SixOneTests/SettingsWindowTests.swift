//
//  SettingsWindowTests.swift
//  SixOneTests

import AppKit
import Testing
@testable import SixOne

@Suite("设置窗口")
@MainActor
struct SettingsWindowTests {
    @Test("标题跟随当前面板")
    func titleFollowsCurrentPane() async throws {
        let (navigation, window) = SettingsTestHost.make()
        defer { window.orderOut(nil) }

        let generalTitle = Localizer.string("General")
        let storageTitle = Localizer.string("Storage")

        let initial = await Wait.until { window.title == generalTitle }
        #expect(initial, "初始标题应是当前面板的名字（实际：\(window.title)）")

        navigation.go(to: .storage)
        let switched = await Wait.until { window.title == storageTitle }
        #expect(switched, "标题跟随当前面板（实际：\(window.title)）")
    }
}
