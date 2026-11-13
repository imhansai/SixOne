//
//  ClipboardFileAccess.swift
//  SixOne
//
//  条目关联文件的解析与导出：bookmark 优先、原路径兜底，图片与文本另存临时文件。
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
            if let scoped = SecurityScopedFileAccess.startScopedURL(
                bookmark: item.securityScopeBookmark,
                path: item.filePath
            ) {
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
            return externalLinkURL(for: item)
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
            return externalLinkURL(for: item)
        case .color:
            return nil
        }
    }

    private func externalLinkURL(for item: ClipboardItem) -> URL? {
        guard let text = item.text, let url = URL(string: text), url.scheme != nil else { return nil }
        return url
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

    /// 可安全交给外部应用的源文件。
    func accessibleSourceURL(for item: ClipboardItem, scopedURL: URL?) -> URL? {
        if let scopedURL { return scopedURL }
        guard let path = item.filePath,
              FileManager.default.isReadableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
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
            return preferredFileURL ?? fileURL(for: item)
        case .link:
            return fileURL(for: item)
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
            return writer.hasText(id: id)
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
