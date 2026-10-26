//
//  SettingsNavigationTests.swift
//  SixOneTests

import SwiftUI
import Testing
@testable import SixOne

@Suite("设置导航")
@MainActor
struct SettingsNavigationTests {
    @Test("前进/后退：栈跟着走")
    func backAndForward() {
        let navigation = SettingsNavigation()
        #expect(navigation.current == .general)
        #expect(!navigation.canGoBack)
        #expect(!navigation.canGoForward)

        navigation.go(to: .privacy)
        #expect(navigation.path == [.general, .privacy])
        #expect(navigation.canGoBack)

        navigation.goBack()
        #expect(navigation.current == .general)
        #expect(navigation.canGoForward)

        navigation.goForward()
        #expect(navigation.current == .privacy)
    }

    @Test("侧栏点回已走过的面板：截断而不是追加，栈不会无限长")
    func revisitingTruncatesInsteadOfGrowing() {
        let navigation = SettingsNavigation()
        navigation.go(to: .privacy)
        navigation.go(to: .shortcuts)

        for _ in 0..<5 {
            navigation.go(to: .privacy)
            navigation.go(to: .shortcuts)
        }

        #expect(navigation.path == [.general, .privacy, .shortcuts])
    }

    @Test("点当前面板是空操作，也不清掉前进栈")
    func clickingCurrentPaneIsNoOp() {
        let navigation = SettingsNavigation()
        navigation.go(to: .storage)
        navigation.goBack()
        #expect(navigation.canGoForward)

        navigation.go(to: .general)

        #expect(navigation.path == [.general])
        #expect(navigation.canGoForward)
    }

    @Test("去一个没走过的面板会清掉前进栈")
    func goingToNewPaneClearsForwardStack() {
        let navigation = SettingsNavigation()
        navigation.go(to: .storage)
        navigation.goBack()

        navigation.go(to: .about)

        #expect(!navigation.canGoForward)
    }

    @Test("关窗重开：回到通用项，前进栈清空，侧栏展开")
    func resetReturnsToGeneral() {
        let navigation = SettingsNavigation()
        navigation.go(to: .privacy)
        navigation.go(to: .about)
        navigation.goBack()
        navigation.columnVisibility = .detailOnly

        navigation.reset()

        #expect(navigation.current == .general, "每次打开设置窗口都从通用项开始")
        #expect(navigation.path == [.general])
        #expect(!navigation.canGoForward)
        #expect(navigation.columnVisibility == .all, "重开时侧栏应恢复展开")
    }
}
