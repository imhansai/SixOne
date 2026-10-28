//
//  ClipboardManager.swift
//  SixOne

import AppKit
import os
import SwiftData

/// 剪贴板监控与历史管理：轮询、去重、触达置顶（原位刷新）、裁剪与回写。
final class ClipboardManager {
    private let settings: SettingsStore
    private let context: ModelContext
    /// 自己持有容器：`ModelContext` 不持有它，容器释放后 context 失效。
    private let container: ModelContainer
    private let pasteboard: PasteboardAccessing
    private let previewCache: ClipboardPreviewCache
    private let frontmostApplication: () -> SourceApplication?
    let events: ClipboardHistoryEventBus
    private var timer: Timer?
    private var retentionTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastChangeCount: Int
    /// 在途捕获；串行排队保证入库顺序与复制顺序一致。
    private var captureTask: Task<Void, Never>?
    private let logger = AppLog.logger("ClipboardManager")

    /// 写库失败出口；只传原因，不携带剪贴板内容。
    var onPersistenceFailure: ((String) -> Void)?

    /// 写盘：失败记日志并上报，不打断剪贴板流程。
    private func save(_ reason: String) {
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

    /// pasteboard / frontmostApplication 可注入隔离测试；pollInterval 为 nil 时不自动轮询。
    init(
        container: ModelContainer,
        settings: SettingsStore,
        events: ClipboardHistoryEventBus,
        previewCache: ClipboardPreviewCache,
        pasteboard: PasteboardAccessing? = nil,
        frontmostApplication: (() -> SourceApplication?)? = nil,
        pollInterval: TimeInterval? = 0.5
    ) {
        self.container = container
        self.context = container.mainContext
        self.settings = settings
        self.events = events
        self.previewCache = previewCache
        self.pasteboard = pasteboard ?? SystemPasteboard()
        self.frontmostApplication = frontmostApplication ?? {
            NSWorkspace.shared.frontmostApplication.map(SourceApplication.init)
        }
        // 只响应启动后的新复制，避免清空历史后重启又补录残留内容。
        self.lastChangeCount = self.pasteboard.changeCount
        if let pollInterval {
            startMonitoring(interval: pollInterval)
            startRetentionSweep()
        }
        trimToRetention()
        // 后台清掉上次运行的导出临时文件（含剪贴板内容副本）。
        let logger = self.logger
        Task.detached(priority: .utility) {
            Self.removeStaleTemporaryExports(logger: logger)
        }
    }

    // MARK: - 监控

    private func startMonitoring(interval: TimeInterval) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Timer 挂在主 RunLoop 上，回调必然在主线程，直接断言隔离。
            MainActor.assumeIsolated {
                self?.pollPasteboard()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 停止计时器：Timer 挂在 RunLoop 上，不失效会一直空转。
    isolated deinit {
        timer?.invalidate()
        retentionTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// 兜底间隔：应用常几周不重启，没有它保留期在无新复制时不生效。
    private static let retentionSweepInterval: TimeInterval = 60 * 60

    private func startRetentionSweep() {
        let timer = Timer(timeInterval: Self.retentionSweepInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.trimToRetention()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retentionTimer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 通知在 main queue 送达，可断言已回到主 actor。
            MainActor.assumeIsolated {
                self?.trimToRetention()
            }
        }
    }

    /// 剪贴板已变化但还没被轮询认领：复制后马上唤出面板时，事件还在流水线里。
    var hasUnpolledPasteboardChange: Bool { pasteboard.changeCount != lastChangeCount }

    /// 轮询一次剪贴板；主线程只做 changeCount、隐私判定与读内容，解析交给后台。
    func pollPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        // 隐私判定须先于读内容：只看类型就拒绝，敏感字节不进内存。
        if pasteboard.isMarkedDoNotRecord {
            logger.notice("跳过被标记为不记录的剪贴板内容")
            return
        }
        let source = frontmostApplication()
        if isIgnoredSource(source) {
            return
        }
        let snapshot = pasteboard.snapshot
        guard !snapshot.items.isEmpty else { return }
        scheduleCapture(snapshot: snapshot, source: source)
    }

    /// 串行排一次捕获：等上一次落定，后台解析后再回主线程入库。
    private func scheduleCapture(snapshot: PasteboardSnapshot, source: SourceApplication?) {
        let previous = captureTask
        captureTask = Task { [weak self] in
            await previous?.value
            let prepared = await Task.detached(priority: .userInitiated) {
                PasteboardEntryParser.prepare(from: snapshot)
            }.value
            guard let self, let prepared else { return }
            self.commit(prepared, source: source)
        }
    }

    func waitForPendingCapture() async {
        await captureTask?.value
    }

    private func commit(_ prepared: PasteboardEntryParser.PreparedCapture, source: SourceApplication?) {
        let entry = prepared.entry
        let fileAccess = prepared.fileAccess
        // 内部写入也可能被轮询到（如预览里 ⌘C 直接写粘贴板），来源只判定一次。
        let isExternal = source?.bundleIdentifier != Bundle.main.bundleIdentifier

        // 内容已存在：原位刷新内容/来源并置顶，去重但不吞事件。
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
            scheduleThumbnail(for: existing, entry: entry)
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
        scheduleThumbnail(for: item, entry: entry)
        trimToRetention()
    }

    private func isIgnoredSource(_ source: SourceApplication?) -> Bool {
        guard let bundleIdentifier = source?.bundleIdentifier else { return false }
        return settings.ignoredApps.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    // MARK: - 持久化维护

    func trimToRetention() {
        guard let interval = settings.historyRetention.interval else { return }
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

    // MARK: - 复制回粘贴板

    func copy(id: UUID) {
        guard let full = fetchFullItem(id: id) else { return }
        copy(full)
    }

    func copy(_ item: ClipboardItem) {
        writeToPasteboard(item)
        // 立即同步 changeCount，免得轮询把内部拷贝当成新复制。
        syncLastChangeCount()
        recordTouch(item)
    }

    /// 只写纯文本（颜色写十六进制色值），并触达置顶。
    func copyAsPlainText(id: UUID) {
        guard let item = fetchFullItem(id: id) else { return }
        copyAsPlainText(item)
    }

    /// 只把关联的第 index 个文件写回剪贴板；解析不到时返回 false。
    @discardableResult
    func copy(_ item: ClipboardItem, fileAt index: Int) -> Bool {
        let urls = resolvedFileURLs(for: item)
        guard urls.indices.contains(index), let url = urls[index] else { return false }
        pasteboard.write(.fileURLs([url]))
        syncLastChangeCount()
        recordTouch(item)
        return true
    }

    func copyAsPlainText(_ item: ClipboardItem) {
        pasteboard.write(.text(plainText(of: item) ?? "", rtf: nil))
        syncLastChangeCount()
        recordTouch(item)
    }

    func copyPlainText(_ text: String) {
        pasteboard.write(.text(text, rtf: nil))
        syncLastChangeCount()
    }

    /// 条目的纯文本形态：正文优先，颜色用十六进制色值；必要时按 id 补齐。
    private func plainText(of item: ClipboardItem) -> String? {
        var text = item.text
        var colorData = item.colorData
        if text == nil || (item.kind == .color && colorData == nil),
           let full = fetchFullItem(id: item.id) {
            text = full.text ?? text
            colorData = full.colorData ?? colorData
        }
        if let text, !text.isEmpty { return text }
        return colorData.flatMap(PasteboardFormat.hexString(ofColorData:))
    }

    func update(_ item: ClipboardItem) {
        // 内容变了，去重快照必须跟着变，否则再次复制命不中去重。
        item.refreshContentKey()
        writeToPasteboard(item)
        syncLastChangeCount()
        recordTouch(item)
    }

    /// 编辑保存：写入新正文并触达；链接不留 RTF，正文清空则删除条目。
    func updateEditedText(id: UUID, text: String, richText: Data?) {
        guard let item = fetchFullItem(id: id) else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            delete(id: id)
            return
        }
        item.text = text
        item.attributedTextData = item.kind == .link ? nil : richText
        update(item)
    }

    func delete(id: UUID) {
        guard let item = fetchFullItem(id: id) else { return }
        context.delete(item)
        save("删除条目")
        events.post(.deleted(id: id))
    }

    /// 逐项解析关联文件的有效路径（与 `allFilePaths` 对应，失败为 nil），优先 bookmark。
    func resolvedFileURLs(for item: ClipboardItem) -> [URL?] {
        SecurityScopedFileAccess.resolvedURLs(for: item)
    }

    func resolvedFileURL(for item: ClipboardItem) -> URL? {
        resolvedFileURLs(for: item).compactMap { $0 }.first
    }

    /// 逐个解析并 start，调用方按 `needsStop` 释放。
    func scopedFileURLs(for item: ClipboardItem) -> [ScopedFileURL?] {
        SecurityScopedFileAccess.startScopedURLs(for: item)
    }

    /// 分享期间持有的文件 URL（会话结束配对 stop）；图片无源文件时落成临时文件。
    func startScopedShareURL(for item: ClipboardItem) -> ScopedFileURL? {
        switch item.kind {
        case .file, .image:
            if let bookmark = item.securityScopeBookmark,
               let url = SecurityScopedFileAccess.startAccess(bookmark: bookmark) {
                return ScopedFileURL(url: url, needsStop: true)
            }
            if let path = item.filePath, FileManager.default.fileExists(atPath: path) {
                return ScopedFileURL(url: URL(fileURLWithPath: path), needsStop: false)
            }
            guard item.kind == .image else { return nil }
            return writeTemporaryImageFile(for: item).map {
                ScopedFileURL(url: $0, needsStop: false)
            }
        case .text, .link, .color:
            return nil
        }
    }

    func startScopedShareURLs(for item: ClipboardItem) -> [ScopedFileURL] {
        SecurityScopedFileAccess.startScopedURLsForSharing(for: item)
    }

    func startScopedShareURL(for item: ClipboardItem, fileAt index: Int) -> ScopedFileURL? {
        SecurityScopedFileAccess.startScopedURLForSharing(for: item, fileAt: index)
    }

    /// 交给其他应用的文件 URL：图片优先源文件，否则把位图落成临时文件。
    /// allowTemporaryCopy 为 false 时只解析真实存在的文件，菜单据此决定是否可用。
    func fileURL(for item: ClipboardItem, allowTemporaryCopy: Bool = true) -> URL? {
        switch item.kind {
        case .text:
            return nil
        case .file:
            return resolvedFileURL(for: item)
        case .image:
            if let url = resolvedFileURL(for: item) { return url }
            guard allowTemporaryCopy else { return nil }
            return writeTemporaryImageFile(for: item)
        case .link:
            guard let text = item.text, let url = URL(string: text), url.scheme != nil else { return nil }
            return url
        case .color:
            return nil
        }
    }

    /// 菜单能否「打开 / 分享」：只读轻量列，不把 imageData 读进内存。
    /// 图片无源文件时再探测位图是否落库。
    func canOpenExternally(id: UUID) -> Bool {
        guard let item = fetchLightItem(id: id) else { return false }
        switch item.kind {
        case .text:
            return false
        case .file:
            return resolvedFileURL(for: item) != nil
        case .image:
            if resolvedFileURL(for: item) != nil { return true }
            return hasInlineImage(id: id)
        case .link:
            guard let text = item.text, let url = URL(string: text) else { return false }
            return url.scheme != nil
        case .color:
            return false
        }
    }

    private func writeTemporaryImageFile(for item: ClipboardItem) -> URL? {
        var data = item.imageData
        if data == nil { data = fetchFullItem(id: item.id)?.imageData }
        guard let data else { return nil }

        let ext = PasteboardFormat.fileExtension(ofBitmap: data)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixone-export/\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        let url = directory.appendingPathComponent(
            "\(Self.exportNameFormatter.string(from: item.lastActivityAt)).\(ext)"
        )
        guard (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    private static let exportNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    /// 导出文件保留 24 小时：留出对方读取时间，又不长期留存剪贴板副本。
    private nonisolated static let temporaryExportLifetime: TimeInterval = 24 * 60 * 60

    nonisolated static func removeStaleTemporaryExports(logger: Logger) {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("sixone-export", isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-temporaryExportLifetime)
        var removed = 0
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            // 读不出时间的留着，宁可占空间也不误删。
            guard let modified, modified < cutoff else { continue }
            if (try? fileManager.removeItem(at: entry)) != nil {
                removed += 1
            }
        }
        if removed > 0 {
            logger.notice("清理了 \(removed, privacy: .public) 个过期导出临时目录")
        }
    }

    private func writeToPasteboard(_ item: ClipboardItem) {
        switch item.kind {
        case .text:
            var attrData = item.attributedTextData
            var text = item.text
            // 列表查询排除了大字段，必要时按 id 补齐。
            if attrData == nil || text == nil, let full = fetchFullItem(id: item.id) {
                attrData = full.attributedTextData ?? attrData
                text = full.text ?? text
            }
            pasteboard.write(.text(text ?? "", rtf: attrData))
        case .image:
            var data = item.imageData
            if data == nil, let full = fetchFullItem(id: item.id) {
                data = full.imageData
            }
            let type = PasteboardFormat.pasteboardType(forContentType: item.contentType)
            pasteboard.write(data.map { .image($0, type: type) } ?? .clear)
        case .file:
            // 一个文件一个 pasteboard item；解析不到路径的用原始路径回写。
            let paths = item.allFilePaths
            guard !paths.isEmpty else {
                pasteboard.write(.clear)
                return
            }
            let resolvedURLs = resolvedFileURLs(for: item)
            let urls = paths.enumerated().map { index, path in
                (index < resolvedURLs.count ? resolvedURLs[index] : nil) ?? URL(fileURLWithPath: path)
            }
            pasteboard.write(.fileURLs(urls))
        case .link:
            var text = item.text
            if text == nil, let full = fetchFullItem(id: item.id) {
                text = full.text
            }
            // 编辑后可能已不是合法 URL，按纯文本写回。
            if let text, let url = URL(string: text), url.scheme != nil {
                pasteboard.write(.url(text))
            } else {
                pasteboard.write(text.map { .text($0, rtf: nil) } ?? .clear)
            }
        case .color:
            var data = item.colorData
            if data == nil, let full = fetchFullItem(id: item.id) {
                data = full.colorData
            }
            pasteboard.write(data.map { .color(text: plainText(of: item), archive: $0) } ?? .clear)
        }
    }

    /// 触达：换新排序键置顶、刷新时间与快照，保存后广播。
    private func recordTouch(_ item: ClipboardItem, isExternal: Bool = false) {
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

    private func syncLastChangeCount() {
        lastChangeCount = pasteboard.changeCount
    }

    /// 按内容 key 取最近一条已有条目；只匹配带快照的条目。
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

    // MARK: - 缩略图

    private var thumbnailTasks: [UUID: Task<Void, Never>] = [:]

    private func scheduleThumbnail(for id: UUID, source: ClipboardThumbnailService.Source) {
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let thumb = await ClipboardThumbnailService.makeThumbnail(from: source) else { return }
            guard let self else { return }
            await MainActor.run {
                guard let item = self.fetchFullItem(id: id),
                      item.thumbnailData != thumb else { return }
                self.previewCache.remove(for: "thumb-\(item.id.uuidString)")
                item.thumbnailData = thumb
                self.save("写入缩略图")
                self.events.post(.thumbnailUpdated(id: id))
            }
        }
        thumbnailTasks[id] = task
        // 落定后摘掉登记，表不能随历史增长。
        Task { [weak self] in
            await task.value
            self?.thumbnailTasks[id] = nil
        }
    }

    /// 等所有在途缩略图落定；最多两轮，收住等待期间新排入的。
    func waitForPendingThumbnails() async {
        for _ in 0..<2 {
            let tasks = Array(thumbnailTasks.values)
            guard !tasks.isEmpty else { return }
            for task in tasks { await task.value }
        }
    }

    private func scheduleThumbnail(for item: ClipboardItem, entry: PasteboardEntryParser.Entry) {
        guard let source = Self.thumbnailSource(for: entry, bookmark: item.securityScopeBookmark) else {
            return
        }
        scheduleThumbnail(for: item.id, source: source)
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
