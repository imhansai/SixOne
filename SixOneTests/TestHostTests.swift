//
//  TestHostTests.swift
//  SixOneTests

import Testing
@testable import SixOne

/// 宿主须认出测试环境，否则会打开真实历史库、抢全局快捷键。
@Suite("测试宿主识别")
struct TestHostTests {
    @Test("测试宿主不进入正常运行路径")
    func hostDetectsUnitTests() {
        #expect(AppDelegate.isRunningUnitTests)
    }
}
