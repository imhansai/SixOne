//
//  SecurityScopedFileAccess.swift
//  SixOne
//
//  沙盒文件访问权：捕获时固化安全作用域 bookmark，解析时 bookmark 优先、原路径兜底，过期重取回写。
//

import Foundation

/// 过期 bookmark 重取出的新数据；调用方应回写库。
nonisolated struct RefreshedBookmark: Sendable, Equatable {
    /// 组内文件的原路径键；单文件为 nil。
    let pathKey: String?
    let data: Data
}

/// 已解析的文件 URL；`needsStop` 表示已 start 安全作用域访问权，调用方须配对一次 stop。
nonisolated struct ScopedFileURL: Sendable {
    let url: URL
    let needsStop: Bool
    let refreshedBookmark: RefreshedBookmark?

    init(url: URL, needsStop: Bool, refreshedBookmark: RefreshedBookmark? = nil) {
        self.url = url
        self.needsStop = needsStop
        self.refreshedBookmark = refreshedBookmark
    }

    func stopAccessIfNeeded() {
        guard needsStop else { return }
        url.stopAccessingSecurityScopedResource()
    }
}

/// 不持有访问权的解析结果。
nonisolated struct ResolvedFileURL: Sendable {
    let url: URL
    let refreshedBookmark: RefreshedBookmark?

    init(url: URL, refreshedBookmark: RefreshedBookmark? = nil) {
        self.url = url
        self.refreshedBookmark = refreshedBookmark
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

    /// 按 bookmark 优先、原路径兜底解析；返回值已释放访问权，只能用于显示或写回，不能继续做文件 I/O。
    static func resolvedFileWithoutAccess(
        bookmark: Data?,
        path: String?,
        pathKey: String? = nil
    ) -> ResolvedFileURL? {
        if let bookmark, let resolved = resolveAndStart(bookmark: bookmark) {
            let refreshed = refreshedBookmark(from: resolved, pathKey: pathKey)
            resolved.url.stopAccessingSecurityScopedResource()
            return ResolvedFileURL(url: resolved.url, refreshedBookmark: refreshed)
        }
        return plainURL(path: path).map { ResolvedFileURL(url: $0) }
    }

    /// 解析并 start 访问权；失败回落原路径（不持有访问权）。
    static func startScopedURL(
        bookmark: Data?,
        path: String?,
        pathKey: String? = nil
    ) -> ScopedFileURL? {
        if let bookmark, let resolved = resolveAndStart(bookmark: bookmark) {
            return ScopedFileURL(
                url: resolved.url,
                needsStop: true,
                refreshedBookmark: refreshedBookmark(from: resolved, pathKey: pathKey)
            )
        }
        return plainURL(path: path).map { ScopedFileURL(url: $0, needsStop: false) }
    }

    /// 解析 bookmark 并 start 访问权；调用方必须配对 stop。
    static func startAccess(bookmark: Data) -> URL? {
        resolveAndStart(bookmark: bookmark)?.url
    }

    /// 解析并 start；`isStale` 表示 bookmark 需重取回写。
    private static func resolveAndStart(bookmark: Data) -> (url: URL, isStale: Bool)? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), url.startAccessingSecurityScopedResource() else { return nil }
        return (url, stale)
    }

    /// stale 时按解析出的 URL 重取；必须在 stop 访问权之前调用。
    private static func refreshedBookmark(
        from resolved: (url: URL, isStale: Bool),
        pathKey: String?
    ) -> RefreshedBookmark? {
        guard resolved.isStale, let data = makeScopeBookmark(for: resolved.url) else { return nil }
        return RefreshedBookmark(pathKey: pathKey, data: data)
    }

    /// 原路径兜底；读不到数据视为不可用。
    private static func plainURL(path: String?) -> URL? {
        guard let path, FileManager.default.isReadableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func decodeBookmarks(_ data: Data?) -> [String: Data] {
        guard let data else { return [:] }
        return (try? JSONDecoder().decode([String: Data].self, from: data)) ?? [:]
    }

    static func encodeBookmarks(_ map: [String: Data]) -> Data? {
        guard !map.isEmpty else { return nil }
        return try? JSONEncoder().encode(map)
    }

    private static func makeScopeBookmark(for path: String) -> Data? {
        makeScopeBookmark(for: URL(fileURLWithPath: path))
    }

    private static func makeScopeBookmark(for url: URL) -> Data? {
        // 读不到的文件建不了 bookmark（如别的应用沙盒容器里的临时文件），直接跳过。
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
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
        return encodeBookmarks(map)
    }
}
