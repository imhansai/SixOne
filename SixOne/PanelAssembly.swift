//
//  PanelAssembly.swift
//  SixOne

import SwiftData

/// 面板子系统的装配：历史库 → 监控 → 面板上下文 → 控制器。
struct PanelAssembly {
    /// 装配持有容器：`ModelContext` 在容器释放后会失效。
    let modelContainer: ModelContainer
    let events: ClipboardHistoryEventBus
    let manager: ClipboardManager
    let store: HistoryListStore
    let context: PanelContext

    init(modelContainer: ModelContainer, settings: SettingsStore) {
        self.modelContainer = modelContainer
        let events = ClipboardHistoryEventBus()
        let caches = PanelCaches()
        let manager = ClipboardManager(
            container: modelContainer,
            settings: settings,
            events: events,
            previewCache: caches.preview
        )
        let repository = SwiftDataHistoryRepository(container: modelContainer)
        let store = HistoryListStore(repository: repository, events: events)
        let context = PanelContext(manager: manager, store: store, caches: caches)

        self.events = events
        self.manager = manager
        self.store = store
        self.context = context
    }

    func makeController() -> ClipboardPanelController {
        ClipboardPanelController(context: context)
    }
}
