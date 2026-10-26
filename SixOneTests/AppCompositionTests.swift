//
//  AppCompositionTests.swift
//  SixOneTests
//  组合根接线：装配漏接是静默故障，用假注册口与内存设置钉住。

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("组合根")
@MainActor
struct AppCompositionTests {
    @Test("面板认领动作、保留时长接上裁剪、快捷键启动即注册")
    func wiresDataPanelAndHotKey() throws {
        let registrar = FakeHotKeyRegistrar()
        let monitor = FakeHotKeyEventMonitor()
        let storage = InMemorySettingsStorage()
        let container = try makeContainer()
        let composition = AppComposition(
            modelContainer: container,
            settings: SettingsStore(storage: storage),
            hotKeyRegistrar: registrar,
            hotKeyEventMonitor: monitor,
            hotKeyStorage: storage
        )

        #expect(composition.panel.context.actions === composition.controller)
        let context = container.mainContext
        let expired = ClipboardItem(kind: .text, text: "过期条目")
        expired.lastActivityAt = Date().addingTimeInterval(-40 * 24 * 3600)
        context.insert(expired)
        try context.save()
        composition.settings.historyRetention = .oneMonth
        #expect(try context.fetch(FetchDescriptor<ClipboardItem>()).isEmpty, "改了保留时长没有立刻裁剪")
        #expect(registrar.registered.count == 1)
        #expect(composition.hotKey.isActive)
        #expect(storage.object(forKey: "globalHotKeyConfigured") == nil)
        #expect(monitor.triggers.count == 1)
    }

    @Test("快捷键注册失败时组合根照常可用，只是状态如实为「没注册上」")
    func survivesHotKeyFailure() throws {
        let registrar = FakeHotKeyRegistrar()
        registrar.isOccupied = { _, _ in true }
        let composition = try makeComposition(registrar: registrar)

        #expect(composition.panel.context.actions === composition.controller)
        #expect(!composition.hotKey.isActive)
        #expect(!composition.hotKey.isRegistered)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ClipboardItem.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func makeComposition(registrar: FakeHotKeyRegistrar) throws -> AppComposition {
        let storage = InMemorySettingsStorage()
        return AppComposition(
            modelContainer: try makeContainer(),
            settings: SettingsStore(storage: storage),
            hotKeyRegistrar: registrar,
            hotKeyEventMonitor: FakeHotKeyEventMonitor(),
            hotKeyStorage: storage
        )
    }
}
