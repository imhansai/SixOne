//
//  ClipboardThumbnailScheduler.swift
//  SixOne
//
//  缩略图调度：后台生成、主线程写回条目并广播；表不随历史增长。
//

import Foundation

final class ClipboardThumbnailScheduler {
    private let writer: ClipboardHistoryWriter
    private let events: ClipboardHistoryEventBus
    private let previewCache: ClipboardPreviewCache
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(
        writer: ClipboardHistoryWriter,
        events: ClipboardHistoryEventBus,
        previewCache: ClipboardPreviewCache
    ) {
        self.writer = writer
        self.events = events
        self.previewCache = previewCache
    }

    func schedule(for item: ClipboardItem, entry: PasteboardEntryParser.Entry) {
        guard let source = Self.thumbnailSource(for: entry, bookmark: item.securityScopeBookmark) else {
            return
        }
        schedule(for: item.id, source: source)
    }

    func schedule(for id: UUID, source: ClipboardThumbnailService.Source) {
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let thumb = await ClipboardThumbnailService.makeThumbnail(from: source) else { return }
            guard let self else { return }
            await MainActor.run {
                guard let item = self.writer.fetchFullItem(id: id),
                      item.thumbnailData != thumb
                        || item.thumbnailVersion != ClipboardItem.currentThumbnailVersion else { return }
                self.previewCache.remove(for: "thumb-\(item.id.uuidString)")
                item.thumbnailData = thumb
                item.thumbnailVersion = ClipboardItem.currentThumbnailVersion
                self.writer.save("写入缩略图")
                self.events.post(.thumbnailUpdated(id: id))
            }
        }
        tasks[id] = task
        // 落定后摘掉登记，表不能随历史增长。
        Task { [weak self] in
            await task.value
            self?.tasks[id] = nil
        }
    }

    /// 等所有在途缩略图落定；最多两轮，收住等待期间新排入的。
    func waitForPendingThumbnails() async {
        for _ in 0..<2 {
            let tasks = Array(tasks.values)
            guard !tasks.isEmpty else { return }
            for task in tasks { await task.value }
        }
    }

    /// 缩略图来源：图片用剪贴板位图（源文件可能在他应用沙盒里，读不到），文件按路径取图。
    /// 文件读不到时不排 Quick Look：quicklookd 拿不到沙盒扩展，只会回文件类型图标。
    nonisolated static func thumbnailSource(
        for entry: PasteboardEntryParser.Entry,
        bookmark: Data?
    ) -> ClipboardThumbnailService.Source? {
        if let imageData = entry.imageData {
            return .bitmap(imageData)
        }
        if let path = entry.filePath {
            guard bookmark != nil || FileManager.default.isReadableFile(atPath: path) else {
                return nil
            }
            return .file(path: path, bookmark: bookmark)
        }
        if let colorData = entry.colorData {
            return .color(colorData)
        }
        return nil
    }
}
