//
//  SecurityScopedFileAccess.swift
//  SixOne
//
//  沙盒文件访问权：捕获时固化安全作用域 bookmark，之后按 bookmark 优先、原路径兜底解析。
//

import Foundation

/// 已解析的文件 URL；`needsStop` 表示已 start 安全作用域访问权，调用方须配对一次 stop。
nonisolated struct ScopedFileURL: Sendable {
    let url: URL
    let needsStop: Bool

    func stopAccessIfNeeded() {
        guard needsStop else { return }
        url.stopAccessingSecurityScopedResource()
    }
}

/// `nonisolated`：捕获路径在后台固化 bookmark，这里只有文件 I/O 与纯值计算。
nonisolated enum SecurityScopedFileAccess {
    /// 单次最多固化 bookmark 的文件数；建 bookmark 是同步 I/O，超出只记路径。
    private static let maxBookmarkedFiles = 100

    /// 一次复制的 bookmark 载荷。
    struct BookmarkPayload: Sendable {
        let bookmark: Data?
        let bookmarks: Data?

        static let empty = BookmarkPayload(bookmark: nil, bookmarks: nil)
    }

    static func payload(forPaths paths: [String]) -> BookmarkPayload {
        guard !paths.isEmpty else { return .empty }
        guard paths.count > 1 else {
            return BookmarkPayload(bookmark: makeScopeBookmark(for: paths[0]), bookmarks: nil)
        }
        return BookmarkPayload(bookmark: nil, bookmarks: makeScopeBookmarks(for: paths))
    }

    /// 逐条解析当前有效路径，与 `allFilePaths` 对齐；访问权在返回前释放。
    static func resolvedURLs(for item: ClipboardItem) -> [URL?] {
        guard item.kind == .file || item.kind == .image else { return [] }
        let paths = item.allFilePaths
        guard !paths.isEmpty else { return [] }
        guard paths.count > 1 else {
            return [resolvedURL(bookmark: item.securityScopeBookmark, path: item.filePath)]
        }
        let bookmarks = decodeBookmarks(item.securityScopeBookmarks)
        return paths.map { resolvedURL(bookmark: bookmarks[$0], path: $0) }
    }

    /// 预览用：解析并 start 访问权，由调用方结束后统一释放。
    static func startScopedURLs(for item: ClipboardItem) -> [ScopedFileURL?] {
        guard item.kind == .file, item.fileCount > 1 else { return [] }
        let bookmarks = decodeBookmarks(item.securityScopeBookmarks)
        return item.allFilePaths.map { startScopedURL(bookmark: bookmarks[$0], path: $0) }
    }

    /// 按 bookmark 优先、原路径兜底解析；返回值已释放访问权。
    static func resolvedURL(bookmark: Data?, path: String?) -> URL? {
        if let bookmark, let url = startAccess(bookmark: bookmark) {
            url.stopAccessingSecurityScopedResource()
            return url
        }
        return plainURL(path: path)
    }

    /// 解析并 start 访问权；失败回落原路径（不持有访问权）。
    static func startScopedURL(bookmark: Data?, path: String?) -> ScopedFileURL? {
        if let bookmark, let url = startAccess(bookmark: bookmark) {
            return ScopedFileURL(url: url, needsStop: true)
        }
        return plainURL(path: path).map { ScopedFileURL(url: $0, needsStop: false) }
    }

    /// 分享整个文件组：逐个解析并 start，只返回当前可用的文件。
    static func startScopedURLsForSharing(for item: ClipboardItem) -> [ScopedFileURL] {
        guard item.kind == .file, item.fileCount > 1 else { return [] }
        let bookmarks = decodeBookmarks(item.securityScopeBookmarks)
        return item.allFilePaths.compactMap { startScopedURL(bookmark: bookmarks[$0], path: $0) }
    }

    /// 分享组内某一个文件：只解析并 start 这一项。
    static func startScopedURLForSharing(for item: ClipboardItem, fileAt index: Int) -> ScopedFileURL? {
        let paths = item.allFilePaths
        guard item.kind == .file, paths.indices.contains(index) else { return nil }
        if paths.count > 1 {
            let bookmarks = decodeBookmarks(item.securityScopeBookmarks)
            return startScopedURL(bookmark: bookmarks[paths[index]], path: paths[index])
        }
        return startScopedURL(bookmark: item.securityScopeBookmark, path: item.filePath)
    }

    /// 解析 bookmark 并 start 访问权；调用方必须配对 stop。
    static func startAccess(bookmark: Data) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }

    /// 原路径兜底；不持有访问权。
    private static func plainURL(path: String?) -> URL? {
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func decodeBookmarks(_ data: Data?) -> [String: Data] {
        guard let data else { return [:] }
        return (try? JSONDecoder().decode([String: Data].self, from: data)) ?? [:]
    }

    private static func makeScopeBookmark(for path: String) -> Data? {
        // 读不到的文件建不了 bookmark（如别的应用沙盒容器里的临时文件），直接跳过。
        guard FileManager.default.isReadableFile(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        return try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// 多文件 bookmark 集合，JSON 编码，避免取窗反复反序列化大字段。
    private static func makeScopeBookmarks(for paths: [String]) -> Data? {
        var map: [String: Data] = [:]
        for path in paths.prefix(maxBookmarkedFiles) {
            if let bookmark = makeScopeBookmark(for: path) {
                map[path] = bookmark
            }
        }
        guard !map.isEmpty else { return nil }
        return try? JSONEncoder().encode(map)
    }
}
