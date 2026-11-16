//
//  ClipboardHistoryWriter.swift
//  SixOne
//
//  历史库写入口：去重、插入、触达与按 id 取数。
//

import Foundation
import SwiftData
import os

final class ClipboardHistoryWriter {
    private let context: ModelContext
    /// 写盘动作；测试注入失败来验证回滚。
    private let persist: () throws -> Void
    let events: ClipboardHistoryEventBus
    private let logger = AppLog.logger("ClipboardHistoryWriter")

    /// 条目写入/触达后通知缩略图调度；由装配处设置，避免反向依赖。
    var onStored: ((ClipboardItem, PasteboardEntryParser.Entry) -> Void)?
    /// 写库失败出口；只传原因，不携带剪贴板内容。
    var onPersistenceFailure: ((String) -> Void)?

    init(
        container: ModelContainer,
        events: ClipboardHistoryEventBus,
        persist: (() throws -> Void)? = nil
    ) {
        let context = container.mainContext
        self.context = context
        self.events = events
        self.persist = persist ?? { try context.save() }
    }

    // MARK: - 写库

    /// 写盘：失败回滚并上报（`reportsFailure` 为 false 时只记日志）。返回是否落盘。
    @discardableResult
    func save(_ reason: String, reportsFailure: Bool = true) -> Bool {
        do {
            try persist()
            return true
        } catch {
            // 不回滚的话，context 里的改动会继续被读到，随后的事件也会让界面与磁盘分叉。
            context.rollback()
            logger.error("保存失败（\(reason, privacy: .public)）：\(error.localizedDescription, privacy: .public)")
            if reportsFailure { onPersistenceFailure?(reason) }
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
            forgetRefreshedBookmarks(for: existing.id)
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

    /// 写别名：只改元数据，不触达置顶、不刷新内容快照。返回是否落盘。
    @discardableResult
    func setAlias(id: UUID, alias: String?) -> Bool {
        guard let item = fetchAliasItem(id: id) else { return false }
        let normalized = ClipboardItem.normalizedAlias(alias)
        guard item.alias != normalized else { return true }
        item.alias = normalized
        guard save("设置别名") else { return false }
        events.post(.rowUpdated(id: id))
        return true
    }

    /// 本会话已回写过的 item+路径键，防止陈旧 bookmark 反复重取写盘。
    private var refreshedBookmarkKeys: Set<String> = []

    /// 回写过期的 bookmark：单文件写列，组内按原路径键更新 JSON；每条路径每会话只写一次。
    @discardableResult
    func refreshSecurityScopeBookmarks(id: UUID, _ refreshes: [RefreshedBookmark]) -> Bool {
        guard !refreshes.isEmpty, let item = fetchLightItem(id: id) else { return false }
        var changed = false
        for refresh in refreshes {
            if item.fileCount > 1 {
                guard let pathKey = refresh.pathKey else { continue }
                guard markRefreshed(id: id, pathKey: pathKey) else { continue }
                var map = SecurityScopedFileAccess.decodeBookmarks(item.securityScopeBookmarks)
                guard map[pathKey] != refresh.data else { continue }
                map[pathKey] = refresh.data
                item.securityScopeBookmarks = SecurityScopedFileAccess.encodeBookmarks(map)
                changed = true
            } else {
                guard markRefreshed(id: id, pathKey: nil) else { continue }
                guard item.securityScopeBookmark != refresh.data else { continue }
                item.securityScopeBookmark = refresh.data
                changed = true
            }
        }
        guard changed else { return true }
        return save("刷新文件 bookmark", reportsFailure: false)
    }

    /// 标记本条路径已回写；本会话重复时返回 false。
    private func markRefreshed(id: UUID, pathKey: String?) -> Bool {
        refreshedBookmarkKeys.insert("\(id.uuidString)|\(pathKey ?? "")").inserted
    }

    /// 重新捕获会带来新 bookmark，解除该条目的回写抑制。
    private func forgetRefreshedBookmarks(for id: UUID) {
        let prefix = id.uuidString + "|"
        refreshedBookmarkKeys = refreshedBookmarkKeys.filter { !$0.hasPrefix(prefix) }
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

    /// 别名读写只取 id 与 alias，避免把路径、书签等列读进内存。
    private func fetchAliasItem(id: UUID) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.id, \.alias]
        return fetchLogged("按 id 取别名") { try context.fetch(descriptor).first }
    }

    /// 按 id 取轻量条目：本次取数不读大字段。
    /// `propertiesToFetch` 只是部分取数，访问未列出的列仍会补取；要正文或位图走 `fetchFullItem`。
    func fetchLightItem(id: UUID) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [
            \.id, \.kindRaw, \.titleSnapshot, \.alias, \.filePath, \.filePaths,
            \.securityScopeBookmark, \.securityScopeBookmarks,
        ]
        return fetchLogged("按 id 取轻量条目") { try context.fetch(descriptor).first }
    }

    func hasText(id: UUID) -> Bool {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == id && $0.text != nil }
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.id]
        let found = fetchLogged("文本存在性探测") { try context.fetch(descriptor) } ?? []
        return !found.isEmpty
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
