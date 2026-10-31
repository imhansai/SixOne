//
//  ClipboardManager.swift
//  SixOne
//
//  剪贴板历史门面：串起轮询捕获、历史读写、粘贴板回写、文件访问与缩略图。
//  具体职责在 `Clipboard*` 协作者里，这里只保留对外接口与定时维护。
//

import AppKit
import os
import SwiftData

final class ClipboardManager {
    private let writer: ClipboardHistoryWriter
    private let fileAccess: ClipboardFileAccess
    private let pasteboardWriter: ClipboardPasteboardWriter
    private let thumbnails: ClipboardThumbnailScheduler
    private let capturePipeline: ClipboardCapturePipeline
    private let imageLoader: ClipboardImageLoader
    private var retentionTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private let logger = AppLog.logger("ClipboardManager")

    let events: ClipboardHistoryEventBus

    /// 写库失败出口；只传原因，不携带剪贴板内容。
    var onPersistenceFailure: ((String) -> Void)? {
        get { writer.onPersistenceFailure }
        set { writer.onPersistenceFailure = newValue }
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
        self.events = events

        let writer = ClipboardHistoryWriter(
            container: container,
            events: events,
            retentionInterval: { [weak settings] in settings?.historyRetention.interval }
        )
        let fileAccess = ClipboardFileAccess(writer: writer)
        let pasteboard = pasteboard ?? SystemPasteboard()
        let pasteboardWriter = ClipboardPasteboardWriter(
            pasteboard: pasteboard,
            writer: writer,
            fileAccess: fileAccess
        )
        let thumbnails = ClipboardThumbnailScheduler(
            writer: writer,
            events: events,
            previewCache: previewCache
        )
        let capturePipeline = ClipboardCapturePipeline(
            pasteboard: pasteboard,
            frontmostApplication: frontmostApplication ?? {
                NSWorkspace.shared.frontmostApplication.map(SourceApplication.init)
            },
            isIgnoredSource: { [weak settings] source in
                guard let settings, let bundleIdentifier = source?.bundleIdentifier else { return false }
                return settings.ignoredApps.contains { $0.bundleIdentifier == bundleIdentifier }
            },
            writer: writer,
            pollInterval: pollInterval
        )

        self.writer = writer
        self.fileAccess = fileAccess
        self.pasteboardWriter = pasteboardWriter
        self.thumbnails = thumbnails
        self.capturePipeline = capturePipeline
        self.imageLoader = ClipboardImageLoader(container: container)

        writer.onStored = { [weak self] item, entry in
            self?.thumbnails.schedule(for: item, entry: entry)
        }
        pasteboardWriter.syncChangeCount = { [weak self] in
            self?.capturePipeline.syncLastChangeCount()
        }

        if pollInterval != nil {
            startRetentionSweep()
        }
        trimToRetention()
        // 后台清掉上次运行的导出临时文件（含剪贴板内容副本）。
        let logger = self.logger
        Task.detached(priority: .utility) {
            ClipboardFileAccess.removeStaleTemporaryExports(logger: logger)
        }
        // 图片去重 key 升级后，旧条目在后台分批重算。
        Task.detached(priority: .utility) {
            await ClipboardContentKeyRepair(container: container).runIfNeeded()
        }
    }

    isolated deinit {
        retentionTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: - 监控

    /// 剪贴板已变化但还没被轮询认领：复制后马上唤出面板时，事件还在流水线里。
    var hasUnpolledPasteboardChange: Bool { capturePipeline.hasUnpolledPasteboardChange }

    func pollPasteboard() {
        capturePipeline.pollPasteboard()
    }

    func waitForPendingCapture() async {
        await capturePipeline.waitForPendingCapture()
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

    // MARK: - 持久化维护

    func trimToRetention() {
        writer.trimToRetention()
    }

    func clearAll() {
        writer.clearAll()
    }

    func delete(id: UUID) {
        writer.delete(id: id)
    }

    // MARK: - 复制回粘贴板

    func copy(id: UUID) {
        pasteboardWriter.copy(id: id)
    }

    func copy(_ item: ClipboardItem) {
        pasteboardWriter.copy(item)
    }

    /// 只写纯文本（颜色写十六进制色值），并触达置顶。
    func copyAsPlainText(id: UUID) {
        pasteboardWriter.copyAsPlainText(id: id)
    }

    /// 只把关联的第 index 个文件写回剪贴板；解析不到时返回 false。
    @discardableResult
    func copy(_ item: ClipboardItem, fileAt index: Int) -> Bool {
        pasteboardWriter.copy(item, fileAt: index)
    }

    func copyAsPlainText(_ item: ClipboardItem) {
        pasteboardWriter.copyAsPlainText(item)
    }

    func copyPlainText(_ text: String) {
        pasteboardWriter.copyPlainText(text)
    }

    func update(_ item: ClipboardItem) {
        pasteboardWriter.update(item)
    }

    /// 编辑保存：写入新正文并触达；链接不留 RTF，正文清空则删除条目。
    func updateEditedText(id: UUID, text: String, richText: Data?) {
        guard let item = writer.fetchFullItem(id: id) else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            writer.delete(id: id)
            return
        }
        item.text = text
        item.attributedTextData = item.kind == .link ? nil : richText
        pasteboardWriter.update(item)
    }

    // MARK: - 文件访问

    /// 逐项解析关联文件的有效路径（与 `allFilePaths` 对应，失败为 nil），优先 bookmark。
    func resolvedFileURLs(for item: ClipboardItem) -> [URL?] {
        fileAccess.resolvedFileURLs(for: item)
    }

    func resolvedFileURL(for item: ClipboardItem) -> URL? {
        fileAccess.resolvedFileURL(for: item)
    }

    /// 逐个解析并 start，调用方按 `needsStop` 释放。
    func scopedFileURLs(for item: ClipboardItem) -> [ScopedFileURL?] {
        fileAccess.scopedFileURLs(for: item)
    }

    func startScopedShareURL(for item: ClipboardItem) -> ScopedFileURL? {
        fileAccess.startScopedShareURL(for: item)
    }

    func startScopedShareURLs(for item: ClipboardItem) -> [ScopedFileURL] {
        fileAccess.startScopedShareURLs(for: item)
    }

    func startScopedShareURL(for item: ClipboardItem, fileAt index: Int) -> ScopedFileURL? {
        fileAccess.startScopedShareURL(for: item, fileAt: index)
    }

    /// 交给其他应用的文件 URL：图片优先源文件，否则把位图落成临时文件。
    /// allowTemporaryCopy 为 false 时只解析真实存在的文件，菜单据此决定是否可用。
    func fileURL(for item: ClipboardItem, allowTemporaryCopy: Bool = true) -> URL? {
        fileAccess.fileURL(for: item, allowTemporaryCopy: allowTemporaryCopy)
    }

    /// 菜单能否「打开 / 分享」：只读轻量列，不把 imageData 读进内存。
    func canOpenExternally(id: UUID) -> Bool {
        fileAccess.canOpenExternally(id: id)
    }

    // MARK: - 取数

    func fetchFullItem(id: UUID) -> ClipboardItem? {
        writer.fetchFullItem(id: id)
    }

    /// 按 id 取轻量条目：本次取数不读大字段。
    func fetchLightItem(id: UUID) -> ClipboardItem? {
        writer.fetchLightItem(id: id)
    }

    func hasInlineImage(id: UUID) -> Bool {
        writer.hasInlineImage(id: id)
    }

    /// 预览用：后台读取完整位图，避免主线程加载大字段。
    func loadImageData(id: UUID) async -> Data? {
        await imageLoader.imageData(id: id)
    }

    // MARK: - 缩略图

    func waitForPendingThumbnails() async {
        await thumbnails.waitForPendingThumbnails()
    }

    /// 旧尺寸缩略图按当前尺寸重算；由列表在显示旧版本时触发。
    func refreshThumbnail(id: UUID) {
        guard let item = writer.fetchFullItem(id: id) else { return }
        thumbnails.refresh(for: item)
    }

    /// 缩略图来源：图片用剪贴板位图（源文件可能在他应用沙盒里，读不到），文件按路径取图。
    nonisolated static func thumbnailSource(
        for entry: PasteboardEntryParser.Entry,
        bookmark: Data?
    ) -> ClipboardThumbnailService.Source? {
        ClipboardThumbnailScheduler.thumbnailSource(for: entry, bookmark: bookmark)
    }
}
