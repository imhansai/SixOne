//
//  ClipboardFileAccess.swift
//  SixOne
//
//  条目关联文件的解析与导出：bookmark 优先、原路径兜底，图片另存临时文件。
//

import Foundation
import os

final class ClipboardFileAccess {
    private let writer: ClipboardHistoryWriter

    init(writer: ClipboardHistoryWriter) {
        self.writer = writer
    }

    // MARK: - 解析

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

    // MARK: - 分享

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

    // MARK: - 打开 / 分享目标

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
        guard let item = writer.fetchLightItem(id: id) else { return false }
        switch item.kind {
        case .text:
            return false
        case .file:
            return resolvedFileURL(for: item) != nil
        case .image:
            if resolvedFileURL(for: item) != nil { return true }
            return writer.hasInlineImage(id: id)
        case .link:
            guard let text = item.text, let url = URL(string: text) else { return false }
            return url.scheme != nil
        case .color:
            return false
        }
    }

    // MARK: - 临时导出

    private func writeTemporaryImageFile(for item: ClipboardItem) -> URL? {
        var data = item.imageData
        if data == nil { data = writer.fetchFullItem(id: item.id)?.imageData }
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
}
