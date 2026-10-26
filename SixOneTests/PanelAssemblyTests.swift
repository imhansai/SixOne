//
//  PanelAssemblyTests.swift
//  SixOneTests

import Foundation
import SwiftData
import Testing
@testable import SixOne

/// 面板装配接线：宿主不走启动流程，接错只会静默不刷新，故显式断言。
@Suite("面板装配")
@MainActor
struct PanelAssemblyTests {
    @Test("剪贴板监控与列表挂在同一条事件总线上")
    func managerAndStoreShareEventBus() async throws {
        let assembly = try makeAssembly()
        #expect(assembly.manager.events === assembly.events)

        // 发事件后等异步重载落定。
        let revisionBefore = assembly.store.dataRevision
        assembly.events.post(.inserted(id: UUID()))
        let didRefresh = await Wait.until(timeout: .seconds(5), interval: .milliseconds(10)) {
            assembly.store.dataRevision != revisionBefore
        }
        #expect(didRefresh, "事件要经「总线 → 主线程任务 → 后台读」三段异步，超时仍未刷新")
    }

    @Test("上下文与装配产出的是同一批对象")
    func contextSharesAssembledObjects() throws {
        let assembly = try makeAssembly()

        #expect(assembly.context.manager === assembly.manager)
        #expect(assembly.context.store === assembly.store)
    }

    @Test("控制器认领面板级动作，视图才能把操作交回面板")
    func controllerClaimsActions() throws {
        let assembly = try makeAssembly()

        // 会真的建面板窗口，整个套件只建一次。
        let controller = assembly.makeController()
        #expect(assembly.context.actions === controller)
    }

    private func makeAssembly() throws -> PanelAssembly {
        let schema = Schema([ClipboardItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return PanelAssembly(
            modelContainer: container,
            settings: SettingsStore(storage: InMemorySettingsStorage())
        )
    }
}
