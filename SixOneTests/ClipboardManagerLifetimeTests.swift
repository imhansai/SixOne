//
//  ClipboardManagerLifetimeTests.swift
//  SixOneTests
//  容器须由管理器持有：context 不持有容器，容器释放后再取数会崩在 SwiftData。

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("管理器的库容器生命周期")
@MainActor
struct ClipboardManagerLifetimeTests {
    @Test("容器交给管理器之后就撤走外部引用，后台取数仍然有效")
    func managerKeepsContainerAlive() async throws {
        let schema = Schema([ClipboardItem.self])
        let settings = SettingsStore(storage: InMemorySettingsStorage())
        var manager: ClipboardManager?
        var itemID: UUID?

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            let item = ClipboardItem(kind: .text, text: "容器生命周期")
            container.mainContext.insert(item)
            try container.mainContext.save()
            itemID = item.id

            manager = ClipboardManager(
                container: container,
                settings: settings,
                events: ClipboardHistoryEventBus(),
                previewCache: PanelCaches().preview,
                pollInterval: nil
            )
        }

        let loaded = try #require(manager?.fetchFullItem(id: itemID ?? UUID()))
        #expect(loaded.text == "容器生命周期")
    }
}
