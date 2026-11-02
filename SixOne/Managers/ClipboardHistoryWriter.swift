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
    /// 写盘动作；测试注入失败来验证回滚。
    private let persist: () throws -> Void
    /// 外部存储（图片/富文本）字节数；内存库恒为 0，测试可注入。
    private let externalByteCount: @MainActor () async -> Int64
    /// 当前预算；nil 表示不限制。
    private let externalByteBudget: @MainActor () -> Int64?
    let events: ClipboardHistoryEventBus
    private let logger = AppLog.logger("ClipboardHistoryWriter")

    /// 条目写入/触达后通知缩略图调度；由装配处设置，避免反向依赖。
    var onStored: ((ClipboardItem, PasteboardEntryParser.Entry) -> Void)?
    /// 写库失败出口；只传原因，不携带剪贴板内容。
    var onPersistenceFailure: ((String) -> Void)?

    init(
        container: ModelContainer,
        events: ClipboardHistoryEventBus,
        retentionInterval: @escaping () -> TimeInterval?,
        persist: (() throws -> Void)? = nil,
        externalByteCount: (@MainActor () async -> Int64)? = nil,
        externalByteBudget: (@MainActor () -> Int64?)? = nil
    ) {
        let context = container.mainContext
        self.container = container
        self.context = context
        self.events = events
        self.retentionInterval = retentionInterval
        self.persist = persist ?? { try context.save() }
        self.externalByteCount = externalByteCount
            ?? Self.makeExternalByteCount(for: container)
        self.externalByteBudget = externalByteBudget
            ?? { HistoryStorageLimit.gigabytes2.bytes }
    }

    /// 图片与富文本都走 `.externalStorage`，落在库旁的隐藏目录里；内存库没有可统计的文件。
    private static func makeExternalByteCount(
        for container: ModelContainer
    ) -> @MainActor () async -> Int64 {
        guard let storeURL = container.configurations
            .first(where: { !$0.isStoredInMemoryOnly })?.url else {
            return { 0 }
        }
        return { await ExternalStorageDirectory.byteCount(forStoreAt: storeURL) }
    }

    // MARK: - 写库

    /// 写盘：失败回滚这一轮改动并上报，不打断剪贴板流程。返回是否落盘。
    @discardableResult
    func save(_ reason: String) -> Bool {
        do {
            try persist()
            return true
        } catch {
            // 不回滚的话，context 里的改动会继续被读到，随后的事件也会让界面与磁盘分叉。
            context.rollback()
            logger.error("保存失败（\(reason, privacy: .public)）：\(error.localizedDescription, privacy: .public)")
            onPersistenceFailure?(reason)
            return false
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
            guard recordTouch(existing, isExternal: isExternal) else { return }
            onStored?(existing, entry)
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
        guard save("新增条目") else { return }
        events.post(.inserted(id: item.id))
        onStored?(item, entry)
    }

    /// 触达：换新排序键置顶、刷新时间与快照，保存后广播。
    @discardableResult
    func recordTouch(_ item: ClipboardItem, isExternal: Bool = false) -> Bool {
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
        guard save("触达置顶") else { return false }
        events.post(.touched(id: item.id, isExternal: isExternal))
        return true
    }

    // MARK: - 维护

    /// 维护操作的单批条数；改小保留期时不至于一次把整段过期集合读进内存。
    private static let maintenanceBatchSize = 500
    /// 预算裁剪的单批条数；比保留期小，超一点不至于删掉几百条。
    private static let budgetTrimBatchSize = 50

    /// 分批裁剪：每批保存并让出一拍，避免大批过期条目连续占住主线程。
    /// 部分批次已落盘后才失败也照常广播，界面据实重载。
    func trimToRetention() async {
        guard let interval = retentionInterval() else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        var didDelete = false
        while true {
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.lastActivityAt < cutoff }
            )
            descriptor.fetchLimit = Self.maintenanceBatchSize
            // 括号包住闭包：尾随闭包会与 guard 语句体混淆。
            guard let expired = fetchLogged("裁剪：查询过期条目", { try context.fetch(descriptor) }),
                  !expired.isEmpty else { break }
            for item in expired {
                context.delete(item)
            }
            guard save("裁剪过期条目") else {
                if didDelete { events.post(.trimmed) }
                return
            }
            didDelete = true
            await Task.yield()
        }
        guard didDelete else { return }
        events.post(.trimmed)
    }

    /// 外部存储字节预算：删行即释放库旁文件；至少保留最新一条。
    func trimToExternalStorageBudget() async {
        guard let budget = externalByteBudget() else { return }
        var bytes = await externalByteCount()
        guard bytes > budget else { return }

        var total = (try? context.fetchCount(FetchDescriptor<ClipboardItem>())) ?? 0
        guard total > 1 else { return }

        var newestDescriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.recencyID, order: .reverse)]
        )
        newestDescriptor.fetchLimit = 1
        newestDescriptor.propertiesToFetch = [\.id]
        // 取不到最新一条就不删，避免误删刚复制的内容。
        guard let newestID = fetchLogged("预算裁剪：查询最新条目", {
            try context.fetch(newestDescriptor).first?.id
        }) else { return }

        var didDelete = false
        var deletedCount = 0
        while bytes > budget, total > 1 {
            // 只挑外部存储条目：正文在内联页里，删了文件也不会缩。
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.imageData != nil || $0.attributedTextData != nil },
                sortBy: [SortDescriptor(\ClipboardItem.recencyID)]
            )
            descriptor.fetchLimit = Self.budgetTrimBatchSize
            // 只取 id，避免把整批大字段读进内存。
            descriptor.propertiesToFetch = [\.id]
            guard let batch = fetchLogged("预算裁剪：查询最旧的外部存储条目", {
                try context.fetch(descriptor)
            }), !batch.isEmpty else { break }

            let deletable = batch.filter { $0.id != newestID }
            guard !deletable.isEmpty else { break }
            for item in deletable {
                context.delete(item)
            }
            guard save("按外部存储预算裁剪") else { break }
            total -= deletable.count
            deletedCount += deletable.count
            didDelete = true
            bytes = await externalByteCount()
            await Task.yield()
        }

        guard didDelete else { return }
        logger.notice("外部存储超出预算，已清理 \(deletedCount, privacy: .public) 条最旧记录")
        events.post(.trimmed)
    }

    func clearAll() {
        // 按 recencyID 游标分批读，避免一次把整库读进数组；仍是一次保存，失败即整体回滚。
        var cursor: UUID?
        var didDelete = false
        while true {
            var descriptor = FetchDescriptor<ClipboardItem>(
                sortBy: [SortDescriptor(\ClipboardItem.recencyID)]
            )
            if let cursor {
                descriptor.predicate = #Predicate { $0.recencyID > cursor }
            }
            descriptor.fetchLimit = Self.maintenanceBatchSize
            guard let batch = fetchLogged("清空：查询条目", { try context.fetch(descriptor) }),
                  !batch.isEmpty else { break }
            for item in batch {
                context.delete(item)
            }
            cursor = batch.last?.recencyID
            didDelete = true
        }
        guard didDelete else { return }
        guard save("清空历史") else { return }
        events.post(.cleared)
    }

    /// 删除一条；已不存在视为已完成。返回是否落盘。
    @discardableResult
    func delete(id: UUID) -> Bool {
        guard let item = fetchFullItem(id: id) else { return true }
        context.delete(item)
        guard save("删除条目") else { return false }
        events.post(.deleted(id: id))
        return true
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
