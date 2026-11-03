//
//  AppActivationPolicyTests.swift
//  SixOneTests
//  常规应用身份按持有者计数，最后一个离场才恢复菜单栏应用。

import AppKit
import Testing
@testable import SixOne

@Suite("应用激活策略")
@MainActor
struct AppActivationPolicyTests {
    private final class State {
        var policy: NSApplication.ActivationPolicy = .accessory
        var activations = 0
        var policyChanges: [NSApplication.ActivationPolicy] = []
    }

    private func makePolicy(state: State, isEnabled: Bool = true) -> AppActivationPolicy {
        AppActivationPolicy(
            isEnabled: isEnabled,
            currentPolicy: { state.policy },
            setPolicy: { policy in
                state.policy = policy
                state.policyChanges.append(policy)
            },
            activate: { state.activations += 1 }
        )
    }

    @Test("最后一个常规窗口离场才恢复菜单栏应用")
    func holdsUntilLastHolder() {
        let state = State()
        let policy = makePolicy(state: state)
        let first = NSObject()
        let second = NSObject()

        policy.beginRegular(first)
        policy.beginRegular(second)
        #expect(state.policy == .regular)
        #expect(state.activations == 0, "切身份不抢激活，激活由窗口显示后单独发起")

        policy.activateApp()
        #expect(state.activations == 1)

        policy.endRegular(first)
        #expect(state.policy == .regular)

        policy.endRegular(second)
        #expect(state.policy == .accessory)
        #expect(state.policyChanges == [.regular, .accessory])
    }

    @Test("已是常规应用时不重复切策略，激活单独发起")
    func alreadyRegularOnlyActivates() {
        let state = State()
        state.policy = .regular
        let policy = makePolicy(state: state)
        let holder = NSObject()

        policy.beginRegular(holder)
        #expect(state.activations == 0)
        #expect(state.policyChanges.isEmpty)

        policy.activateApp()
        #expect(state.activations == 1)

        policy.endRegular(holder)
        #expect(state.policy == .accessory)
        #expect(state.policyChanges == [.accessory])
    }

    @Test("测试环境禁用时不碰系统策略")
    func disabledDoesNothing() {
        let state = State()
        let policy = makePolicy(state: state, isEnabled: false)
        let holder = NSObject()

        policy.beginRegular(holder)
        policy.activateApp()
        policy.endRegular(holder)

        #expect(state.policy == .accessory)
        #expect(state.activations == 0)
        #expect(state.policyChanges.isEmpty)
    }
}
