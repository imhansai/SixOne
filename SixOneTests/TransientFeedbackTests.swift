//
//  TransientFeedbackTests.swift
//  SixOneTests
//  短暂反馈计时：新调度取消旧调度，取消后不再触发。
//

import Foundation
import Testing
@testable import SixOne

@Suite("短暂反馈计时")
@MainActor
struct TransientFeedbackTests {
    @Test("新调度取消旧调度，只有最后一次生效")
    func replacesPreviousSchedule() async {
        let feedback = TransientFeedback()
        var fired: [Int] = []
        feedback.schedule(after: 0.1) { fired.append(1) }
        feedback.schedule(after: 0.2) { fired.append(2) }

        #expect(await Wait.until { fired == [2] })
        #expect(fired == [2])
    }

    @Test("取消后不再触发")
    func cancelStopsPendingAction() async {
        let feedback = TransientFeedback()
        var fired = false
        feedback.schedule(after: 0.05) { fired = true }
        feedback.cancel()

        await Wait.settle(milliseconds: 150)
        #expect(!fired)
    }
}
