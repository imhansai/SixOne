//
//  ClipboardHistoryWriter.swift
//  SixOne
//
//  历史库写入口：去重、插入、触达、裁剪、清空与按 id 取数。
//

import Foundation
import SwiftData
import os

final class ClipboardHistoryWriter {
    private let container: ModelContainer
    private let context: ModelContext
    private let retentionInterval: () -> TimeInterval?
    let events: ClipboardHistoryEventBus
    private let logger = AppLog.logger("ClipboardHistoryWriter")

    /// 条目写入/触达后通知缩略图调度；由装配处设置，避免反向依赖。
    var onStored: ((ClipboardItem, PasteboardEntryParser.Entry) -> Void)?
    /// 写库失败出口；只传原因，不携带剪贴板内容。
    var onPersistenceFailure: ((String) -> Void)?

    init(
        container: ModelContainer,
        events: ClipboardHistoryEventBus,
        retentionInterval: @escaping () -> TimeInterval?
    ) {
        self.container = container
        self.context = container.mainContext
        self.events = events
        self.retentionInterval = retentionInterval
    }

    // MARK: - 写库

    /// 写盘：失败记日志并上报，不打断剪贴板流程。
    func save(_ reason: String) {
        do {
            try context.save()
        } catch {
            logger.error("保存失败（\(reason, privacy: .public)）：\(error.localizedDescription, privacy: .public)")
            onPersistenceFailure?(reason)
        }
    }

    private func fetchLogged<T>(_ what: String, _ body: () throws -> T?) -> T? {
        do {
            return try body()
        } catch {
            logger.error("读取失败（\(what, privacy: .public)）：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 解析结果入库：内容已存在则原位刷新并置顶，否则新增。
    func commit(_ prepared: PasteboardEntryParser.PreparedCapture, source: SourceApplication?) {
        let entry = prepared.entry
        let fileAccess = prepared.fileAccess
        // 内部写入也可能被轮询到（如预览里 ⌘C 直接写粘贴板），来源只判定一次。
        let isExternal = source?.bundleIdentifier != Bundle.main.bundleIdentifier

        if let existing = existingItem(forContentKey: entry.contentKey) {
            existing.kind = entry.kind
            existing.text = entry.text
            existing.attributedTextData = entry.attributedTextData
            existing.imageData = entry.imageData
            existing.filePath = entry.filePath
            existing.filePaths = entry.groupedFilePaths
            existing.contentType = entry.contentType
            existing.colorData = entry.colorData
            // 内部写入触发的轮询保留原来源，避免角标被改成 SixOne 自身。
            if isExternal {
                existing.sourceAppBundleIdentifier = source?.bundleIdentifier
                existing.sourceAppName = source?.name
            }
            existing.securityScopeBookmark = fileAccess.bookmark
            existing.securityScopeBookmarks = fileAccess.bookmarks
            recordTouch(existing, isExternal: isExternal)
            onStored?(existing, entry)
            trimToRetention()
            return
        }

        let item = ClipboardItem(
            kind: entry.kind,
            text: entry.text,
            attributedTextData: entry.attributedTextData,
            imageData: entry.imageData,
            filePath: entry.filePath,
            filePaths: entry.groupedFilePaths,
            contentType: entry.contentType,
            colorData: entry.colorData,
            sourceAppBundleIdentifier: source?.bundleIdentifier,
            sourceAppName: source?.name
        )
        item.refreshTitleSnapshot()
        item.refreshContentKey()
        item.securityScopeBookmark = fileAccess.bookmark
        item.securityScopeBookmarks = fileAccess.bookmarks
        context.insert(item)
        save("新增条目")
        events.post(.inserted(id: item.id))
        onStored?(item, entry)
        trimToRetention()
    }

    /// 触达：换新排序键置顶、刷新时间与快照，保存后广播。
    func recordTouch(_ item: ClipboardItem, isExternal: Bool = false) {
        item.lastActivityAt = Date()
        item.recencyID = OrderedUUID.make()
        // 标题快照可能依赖 lastActivityAt，触达后统一刷新。
        item.refreshTitleSnapshot()
        if item.kind == .text || item.kind == .link {
            item.refreshSearchText()
        } else if item.kind == .color {
            item.refreshColorSearchText()
        }
        item.refreshFilePathsSearchText()
        save("触达置顶")
        events.post(.touched(id: item.id, isExternal: isExternal))
    }

    // MARK: - 维护

    func trimToRetention() {
        guard let interval = retentionInterval() else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.lastActivityAt < cutoff }
        )
        // 括号包住闭包：尾随闭包会与 guard 语句体混淆。
        guard let expired = fetchLogged("裁剪：查询过期条目", { try context.fetch(descriptor) }),
              !expired.isEmpty else { return }
        for item in expired {
            context.delete(item)
        }
        save("裁剪过期条目")
        events.post(.trimmed)
    }

    func clearAll() {
        let descriptor = FetchDescriptor<ClipboardItem>()
        let all = fetchLogged("清空：查询全部条目") { try context.fetch(descriptor) } ?? []
        for item in all {
            context.delete(item)
        }
        save("清空历史")
        if !all.isEmpty {
            events.post(.cleared)
        }
    }

    func delete(id: UUID) {
        guard let item = fetchFullItem(id: id) else { return }
        context.delete(item)
        save("删除条目")
        events.post(.deleted(id: id))
    }

    // MARK: - 取数

    private func existingItem(forContentKey key: String) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentKeySnapshot == key },
            sortBy: [SortDescriptor(\ClipboardItem.recencyID, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return fetchLogged("去重：按内容 key 查已有条目") { try context.fetch(descriptor).first }
    }

    func fetchFullItem(id: UUID) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetchLogged("按 id 取完整条目") { try context.fetch(descriptor).first }
    }

    /// 按 id 取轻量条目：本次取数不读大字段。
    /// `propertiesToFetch` 只是部分取数，访问未列出的列仍会补取；要正文或位图走 `fetchFullItem`。
    func fetchLightItem(id: UUID) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [
            \.id, \.kindRaw, \.titleSnapshot, \.filePath, \.filePaths,
            \.securityScopeBookmark, \.securityScopeBookmarks,
        ]
        return fetchLogged("按 id 取轻量条目") { try context.fetch(descriptor).first }
    }

    func hasInlineImage(id: UUID) -> Bool {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == id && $0.imageData != nil }
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.id]
        let found = fetchLogged("位图存在性探测") { try context.fetch(descriptor) } ?? []
        return !found.isEmpty
    }
}
