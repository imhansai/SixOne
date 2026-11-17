//
//  ClipboardFileAccess.swift
//  SixOne
//
//  条目关联文件的解析与导出：bookmark 优先、原路径兜底、过期回写，图片与文本另存临时文件。
//

import Foundation
import os

final class ClipboardFileAccess {
    private let writer: ClipboardHistoryWriter

    init(writer: ClipboardHistoryWriter) {
        self.writer = writer
    }

    // MARK: - 解析

    /// 逐项解析关联文件的有效路径（与 `allFilePaths` 对应，失败为 nil），优先 bookmark；过期顺手回写。
    func resolvedFileURLs(for item: ClipboardItem) -> [URL?] {
        guard item.kind == .file || item.kind == .image else { return [] }
        let paths = item.allFilePaths
        guard !paths.isEmpty else { return [] }
        let resolved: [ResolvedFileURL?]
        if paths.count > 1 {
            let bookmarks = SecurityScopedFileAccess.decodeBookmarks(item.securityScopeBookmarks)
            resolved = paths.map {
                SecurityScopedFileAccess.resolvedFileWithoutAccess(bookmark: bookmarks[$0], path: $0, pathKey: $0)
            }
        } else {
            resolved = [SecurityScopedFileAccess.resolvedFileWithoutAccess(
                bookmark: item.securityScopeBookmark,
                path: item.filePath
            )]
        }
        writeBackRefreshedBookmarks(resolved.compactMap { $0?.refreshedBookmark }, for: item)
        return resolved.map { $0?.url }
    }

    func resolvedFileURL(for item: ClipboardItem) -> URL? {
        resolvedFileURLs(for: item).compactMap { $0 }.first
    }

    /// 逐个解析并 start，调用方按 `needsStop` 释放；过期顺手回写。
    func scopedFileURLs(for item: ClipboardItem) -> [ScopedFileURL?] {
        guard item.kind == .file, item.fileCount > 1 else { return [] }
        let bookmarks = SecurityScopedFileAccess.decodeBookmarks(item.securityScopeBookmarks)
        let resolved = item.allFilePaths.map {
            SecurityScopedFileAccess.startScopedURL(bookmark: bookmarks[$0], path: $0, pathKey: $0)
        }
        writeBackRefreshedBookmarks(resolved.compactMap { $0?.refreshedBookmark }, for: item)
        return resolved
    }

    /// 单文件（含图片）解析并 start；过期顺手回写。
    func startScopedFileURL(for item: ClipboardItem) -> ScopedFileURL? {
        let resolved = SecurityScopedFileAccess.startScopedURL(
            bookmark: item.securityScopeBookmark,
            path: item.filePath
        )
        writeBackRefreshedBookmark(resolved?.refreshedBookmark, for: item)
        return resolved
    }

    // MARK: - 分享

    /// 分享期间持有的文件 URL（会话结束配对 stop）；图片无源文件时落成临时文件。
    func startScopedShareURL(for item: ClipboardItem) -> ScopedFileURL? {
        switch item.kind {
        case .file, .image:
            if let scoped = startScopedFileURL(for: item) {
                return scoped
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
        guard item.kind == .file, item.fileCount > 1 else { return [] }
        let bookmarks = SecurityScopedFileAccess.decodeBookmarks(item.securityScopeBookmarks)
        let resolved = item.allFilePaths.compactMap {
            SecurityScopedFileAccess.startScopedURL(bookmark: bookmarks[$0], path: $0, pathKey: $0)
        }
        writeBackRefreshedBookmarks(resolved.compactMap(\.refreshedBookmark), for: item)
        return resolved
    }

    func startScopedShareURL(for item: ClipboardItem, fileAt index: Int) -> ScopedFileURL? {
        let paths = item.allFilePaths
        guard item.kind == .file, paths.indices.contains(index) else { return nil }
        let resolved: ScopedFileURL?
        if paths.count > 1 {
            let bookmarks = SecurityScopedFileAccess.decodeBookmarks(item.securityScopeBookmarks)
            resolved = SecurityScopedFileAccess.startScopedURL(
                bookmark: bookmarks[paths[index]],
                path: paths[index],
                pathKey: paths[index]
            )
        } else {
            resolved = SecurityScopedFileAccess.startScopedURL(bookmark: item.securityScopeBookmark, path: item.filePath)
        }
        writeBackRefreshedBookmark(resolved?.refreshedBookmark, for: item)
        return resolved
    }

    /// 回写过期 bookmark，下次解析不再走 stale 路径。
    private func writeBackRefreshedBookmarks(_ refreshes: [RefreshedBookmark], for item: ClipboardItem) {
        guard !refreshes.isEmpty else { return }
        writer.refreshSecurityScopeBookmarks(id: item.id, refreshes)
    }

    private func writeBackRefreshedBookmark(_ refresh: RefreshedBookmark?, for item: ClipboardItem) {
        guard let refresh else { return }
        writer.refreshSecurityScopeBookmarks(id: item.id, [refresh])
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
            return item.linkURL
        case .color:
            return nil
        }
    }

    /// 打开方式的后备落点：文本与内联图片落成临时文件。
    func openWithURL(for item: ClipboardItem) -> URL? {
        switch item.kind {
        case .text:
            return writeTemporaryTextFile(for: item)
        case .file:
            return resolvedFileURL(for: item)
        case .image:
            return writeTemporaryImageFile(for: item) ?? resolvedFileURL(for: item)
        case .link:
            return item.linkURL
        case .color:
            return nil
        }
    }

    /// 打开方式枚举用的文件：源文件可读就用它，否则用 0 字节占位文件。
    func openWithEnumerationURL(for item: ClipboardItem, scopedSourceURL: URL?) -> URL? {
        switch item.kind {
        case .image:
            if let source = accessibleSourceURL(for: item, scopedURL: scopedSourceURL) {
                return source
            }
            guard let data = item.imageData else { return nil }
            return writeTemporaryPlaceholder(
                fileExtension: PasteboardFormat.fileExtension(ofBitmap: data),
                date: item.lastActivityAt
            )
        case .text:
            return writeTemporaryPlaceholder(
                fileExtension: textExportFileExtension(for: item),
                date: item.lastActivityAt
            )
        case .file, .link, .color:
            return nil
        }
    }

    /// 可安全交给外部应用的源文件：先校验视图持有的 URL，再按 bookmark 解析。
    func accessibleSourceURL(for item: ClipboardItem, scopedURL: URL?) -> URL? {
        if let scopedURL, FileManager.default.isReadableFile(atPath: scopedURL.path) {
            return scopedURL
        }
        guard let resolved = SecurityScopedFileAccess.resolvedFileWithoutAccess(
            bookmark: item.securityScopeBookmark,
            path: item.filePath
        ) else { return nil }
        writeBackRefreshedBookmark(resolved.refreshedBookmark, for: item)
        return resolved.url
    }

    /// 统一的打开落点：源文件可安全访问时优先，否则按类型回退。
    func openTarget(
        for item: ClipboardItem,
        scopedSourceURL: URL?,
        preferredFileURL: URL?
    ) -> URL? {
        switch item.kind {
        case .image:
            return accessibleSourceURL(for: item, scopedURL: scopedSourceURL) ?? openWithURL(for: item)
        case .text:
            return openWithURL(for: item)
        case .file:
            if let preferredFileURL,
               FileManager.default.isReadableFile(atPath: preferredFileURL.path) {
                return preferredFileURL
            }
            guard item.fileCount <= 1 else { return nil }
            return fileURL(for: item)
        case .link:
            return fileURL(for: item)
        case .color:
            return nil
        }
    }

    /// 在访达中定位用：只要路径存在即可，不要求可读。
    func revealURLs(for item: ClipboardItem) -> [URL] {
        guard item.kind == .file || item.kind == .image else { return [] }
        let resolved = resolvedFileURLs(for: item)
        return item.allFilePaths.enumerated().compactMap { index, path in
            if resolved.indices.contains(index), let url = resolved[index] { return url }
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    // MARK: - 菜单可用性解析

    /// 纯解析结果；不碰库，可在后台调用。
    nonisolated struct FileAccessEvaluation: Sendable {
        let canOpen: Bool
        let canReveal: Bool
        let refreshedBookmarks: [RefreshedBookmark]
    }

    /// 逐路径解析，文件组能确定答案时短路。
    nonisolated static func evaluateFileAccess(
        paths: [String],
        bookmark: Data?,
        bookmarksJSON: Data?,
        needsReveal: Bool
    ) -> FileAccessEvaluation {
        guard !paths.isEmpty else {
            return FileAccessEvaluation(canOpen: false, canReveal: false, refreshedBookmarks: [])
        }
        let isGroup = paths.count > 1
        let bookmarks = isGroup ? SecurityScopedFileAccess.decodeBookmarks(bookmarksJSON) : [:]
        var canOpen = false
        var canReveal = false
        var refreshedBookmarks: [RefreshedBookmark] = []
        for path in paths {
            if let resolved = SecurityScopedFileAccess.resolvedFileWithoutAccess(
                bookmark: isGroup ? bookmarks[path] : bookmark,
                path: path,
                pathKey: isGroup ? path : nil
            ) {
                canOpen = true
                canReveal = true
                if let refreshed = resolved.refreshedBookmark {
                    refreshedBookmarks.append(refreshed)
                }
            } else if needsReveal, FileManager.default.fileExists(atPath: path) {
                // 存在但不可读：不能打开，仍可在访达中定位。
                canReveal = true
            }
            if canOpen { break }
        }
        return FileAccessEvaluation(
            canOpen: canOpen,
            canReveal: canReveal,
            refreshedBookmarks: refreshedBookmarks
        )
    }

    /// 后台探测入口：给出菜单结论，交回过期 bookmark。
    nonisolated static func resolveCapabilities(
        for request: FileCapabilityRequest
    ) -> FileCapabilityResolution {
        switch request.kind {
        case .text:
            return FileCapabilityResolution(
                capabilities: FileCapabilities(canOpen: request.hasText, canReveal: false),
                refreshedBookmarks: []
            )
        case .link:
            return FileCapabilityResolution(
                capabilities: FileCapabilities(canOpen: request.isOpenableLink, canReveal: false),
                refreshedBookmarks: []
            )
        case .color:
            return FileCapabilityResolution(capabilities: .none, refreshedBookmarks: [])
        case .image, .file:
            let access = evaluateFileAccess(
                paths: request.paths,
                bookmark: request.bookmark,
                bookmarksJSON: request.bookmarks,
                needsReveal: true
            )
            let canOpen = access.canOpen || (request.kind == .image && request.hasInlineImage)
            return FileCapabilityResolution(
                capabilities: FileCapabilities(canOpen: canOpen, canReveal: access.canReveal),
                refreshedBookmarks: access.refreshedBookmarks
            )
        }
    }

    // MARK: - 临时导出

    private func writeTemporaryImageFile(for item: ClipboardItem) -> URL? {
        var data = item.imageData
        if data == nil { data = writer.fetchFullItem(id: item.id)?.imageData }
        guard let data else { return nil }
        return writeTemporaryExport(
            data: data,
            fileExtension: PasteboardFormat.fileExtension(ofBitmap: data),
            date: item.lastActivityAt
        )
    }

    private func writeTemporaryTextFile(for item: ClipboardItem) -> URL? {
        let fileExtension = textExportFileExtension(for: item)
        if let rtf = item.attributedTextData {
            return writeTemporaryExport(data: rtf, fileExtension: fileExtension, date: item.lastActivityAt)
        }
        guard let text = item.text else { return nil }
        return writeTemporaryExport(data: Data(text.utf8), fileExtension: fileExtension, date: item.lastActivityAt)
    }

    private func textExportFileExtension(for item: ClipboardItem) -> String {
        item.attributedTextData != nil ? "rtf" : "txt"
    }

    private func writeTemporaryPlaceholder(fileExtension: String, date: Date) -> URL? {
        writeTemporaryExport(data: Data(), fileExtension: fileExtension, date: date)
    }

    private func writeTemporaryExport(data: Data, fileExtension: String, date: Date) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixone-export/\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        let url = directory.appendingPathComponent(
            "\(Self.exportNameFormatter.string(from: date)).\(fileExtension)"
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
