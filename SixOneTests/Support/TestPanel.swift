//
//  TestPanel.swift
//  SixOneTests
//
//  列表视图测试的 `PanelContext` 工厂。
//

@testable import SixOne

@MainActor
enum TestPanel {
    /// 建一个能撑起列表视图的 `PanelContext`；管理器持有容器，库不会随 harness 释放。
    static func context() throws -> PanelContext {
        let harness = try ClipboardHarness()
        return PanelContext(
            manager: harness.manager,
            store: HistoryListStore(repository: FakeHistoryRepository(), events: ClipboardHistoryEventBus()),
            caches: PanelCaches()
        )
    }
}
