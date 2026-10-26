//
//  ClipboardHarness.swift
//  SixOneTests
//

import Foundation
import SwiftData
@testable import SixOne

/// 前台应用取值盒，测试中途可换来源。
@MainActor
final class FrontmostBox {
    var source: SourceApplication?
}

/// 事件记录器。
@MainActor
final class EventRecorder {
    private(set) var events: [ClipboardHistoryEvent] = []
    func record(_ event: ClipboardHistoryEvent) { events.append(event) }
}

/// 测试台：内存库 + 内存剪贴板 + 内存设置。
@MainActor
struct ClipboardHarness {
    /// 必须持有：`ModelContext` 在容器释放后失效。
    let container: ModelContainer
    let context: ModelContext
    let settings: SettingsStore
    let recorder: EventRecorder
    let frontmost: FrontmostBox
    let pasteboard: FakePasteboard
    let manager: ClipboardManager

    /// `seed` 在管理器构造前写入种子数据（用于测启动即裁剪）。
    init(
        ignoredApps: [IgnoredApplication]? = nil,
        retention: HistoryRetention? = nil,
        seed: ((ModelContext) throws -> Void)? = nil
    ) throws {
        let schema = Schema([ClipboardItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let settings = SettingsStore(storage: InMemorySettingsStorage())
        if let ignoredApps {
            settings.ignoredApps = ignoredApps
        }
        if let retention {
            settings.historyRetention = retention
        }
        try seed?(container.mainContext)

        let events = ClipboardHistoryEventBus()
        let recorder = EventRecorder()
        events.observe { [recorder] event in recorder.record(event) }
        let frontmost = FrontmostBox()
        let pasteboard = FakePasteboard()
        let caches = PanelCaches()

        self.container = container
        self.context = container.mainContext
        self.settings = settings
        self.recorder = recorder
        self.frontmost = frontmost
        self.pasteboard = pasteboard
        self.manager = ClipboardManager(
            container: container,
            settings: settings,
            events: events,
            previewCache: caches.preview,
            pasteboard: pasteboard,
            frontmostApplication: { frontmost.source },
            pollInterval: nil
        )
    }

    /// 库里的条目，最新在前。
    func itemsNewestFirst() -> [ClipboardItem] {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.recencyID, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 驱动一次捕获并等后台解析入库。
    func pollAndWait() async {
        manager.pollPasteboard()
        await manager.waitForPendingCapture()
    }

    /// 等在途缩略图任务落定。
    func drainThumbnails() async {
        await manager.waitForPendingThumbnails()
    }
}
