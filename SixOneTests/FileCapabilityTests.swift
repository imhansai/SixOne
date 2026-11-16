//
//  FileCapabilityTests.swift
//  SixOneTests
//  菜单文件能力：纯解析结果与缓存/后台探测行为。
//

import Foundation
import Testing
@testable import SixOne

@Suite("文件能力解析")
@MainActor
struct FileCapabilityResolutionTests {
    @Test("文件条目：存在可读 → 可打开、可揭示；缺失 → 都不可用")
    func fileExistence() throws {
        let existing = try TemporaryFiles.makeFile(prefix: "sixone-capability", contents: "x")
        defer { try? FileManager.default.removeItem(at: existing) }

        let found = ClipboardFileAccess.resolveCapabilities(for: request(kind: .file, paths: [existing.path]))
        #expect(found.capabilities == FileCapabilities(canOpen: true, canReveal: true))

        let missing = ClipboardFileAccess.resolveCapabilities(for: request(kind: .file, paths: ["/definitely/not/here"]))
        #expect(missing.capabilities == .none)
    }

    @Test("图片条目：源文件缺失但内联位图在 → 仍可打开，不可揭示")
    func imageFallsBackToInlineBitmap() {
        let resolution = ClipboardFileAccess.resolveCapabilities(for: request(
            kind: .image,
            paths: ["/definitely/not/here.png"],
            hasInlineImage: true
        ))

        #expect(resolution.capabilities == FileCapabilities(canOpen: true, canReveal: false))
    }

    @Test("文件组：任一文件可达即满足，不必全部解析")
    func fileGroupUsesAnyReachableFile() throws {
        let existing = try TemporaryFiles.makeFile(prefix: "sixone-capability-group", contents: "x")
        defer { try? FileManager.default.removeItem(at: existing) }

        let resolution = ClipboardFileAccess.resolveCapabilities(for: request(
            kind: .file,
            paths: [existing.path, "/definitely/not/here"]
        ))
        #expect(resolution.capabilities == FileCapabilities(canOpen: true, canReveal: true))
    }

    @Test("文件组：按原路径键用 bookmark 找回已移动的文件")
    func fileGroupResolvesPerPathBookmarks() throws {
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-capability-bookmarks")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: first)
        let missing = directory.appendingPathComponent("b.txt")
        let bookmarks = try #require(
            SecurityScopedFileAccess.payload(forPaths: [first.path, missing.path]).bookmarks
        )

        let renamed = directory.appendingPathComponent("a-改.txt")
        try FileManager.default.moveItem(at: first, to: renamed)

        let resolution = ClipboardFileAccess.resolveCapabilities(for: FileCapabilityRequest(
            itemID: UUID(),
            recencyID: UUID(),
            kind: .file,
            paths: [first.path, missing.path],
            bookmark: nil,
            bookmarks: bookmarks,
            hasInlineImage: false,
            hasText: false,
            isOpenableLink: false
        ))

        #expect(resolution.capabilities == FileCapabilities(canOpen: true, canReveal: true))
        #expect(resolution.refreshedBookmarks.map(\.pathKey) == [first.path])
    }

    @Test("文本与链接只按内容判定；颜色没有外部落点")
    func contentKinds() {
        let text = ClipboardFileAccess.resolveCapabilities(
            for: request(kind: .text, paths: [], hasText: true)
        )
        #expect(text.capabilities == FileCapabilities(canOpen: true, canReveal: false))

        let emptyText = ClipboardFileAccess.resolveCapabilities(
            for: request(kind: .text, paths: [], hasText: false)
        )
        #expect(emptyText.capabilities == .none)

        let link = ClipboardFileAccess.resolveCapabilities(
            for: request(kind: .link, paths: [], isOpenableLink: true)
        )
        #expect(link.capabilities == FileCapabilities(canOpen: true, canReveal: false))

        let color = ClipboardFileAccess.resolveCapabilities(for: request(kind: .color, paths: []))
        #expect(color.capabilities == .none)
    }

    private func request(
        kind: ClipboardItemKind,
        paths: [String],
        hasInlineImage: Bool = false,
        hasText: Bool = false,
        isOpenableLink: Bool = false
    ) -> FileCapabilityRequest {
        FileCapabilityRequest(
            itemID: UUID(),
            recencyID: UUID(),
            kind: kind,
            paths: paths,
            bookmark: nil,
            bookmarks: nil,
            hasInlineImage: hasInlineImage,
            hasText: hasText,
            isOpenableLink: isOpenableLink
        )
    }
}

@Suite("文件能力缓存")
@MainActor
struct PanelFileCapabilityCacheTests {
    @Test("未命中先用乐观值，后台结果落定后生效；TTL 内不重复解析")
    func resolvesInBackgroundAndCaches() async throws {
        let resolver = ResolverRecorder(result: resolution(canOpen: false, canReveal: false))
        let cache = PanelFileCapabilityCache(
            ttl: 60,
            notificationCenter: nil,
            resolver: resolver.resolve
        )
        let request = makeRequest(kind: .file)
        let optimistic = FileCapabilities(canOpen: true, canReveal: true)
        let resolved = FileCapabilities(canOpen: false, canReveal: false)

        #expect(cache.capabilities(for: request) == optimistic)
        #expect(await Wait.until { cache.cachedCapabilities(for: request.itemID) == resolved })
        #expect(resolver.count == 1)

        #expect(cache.capabilities(for: request) == resolved)
        #expect(resolver.count == 1, "TTL 内应直接命中缓存")
    }

    @Test("TTL 到期：先沿用旧值，同时触发一次后台刷新")
    func staleEntryRefreshesInBackground() async throws {
        let clock = TestClock()
        let resolver = ResolverRecorder(result: resolution(canOpen: false, canReveal: false))
        let cache = PanelFileCapabilityCache(
            ttl: 5,
            notificationCenter: nil,
            now: { clock.date },
            resolver: resolver.resolve
        )
        let request = makeRequest(kind: .file)
        let resolved = FileCapabilities(canOpen: false, canReveal: false)

        _ = cache.capabilities(for: request)
        #expect(await Wait.until { cache.cachedCapabilities(for: request.itemID) == resolved })
        #expect(resolver.count == 1)

        clock.date = clock.date.addingTimeInterval(6)
        #expect(cache.capabilities(for: request) == resolved, "过期时先返回旧值")
        #expect(await Wait.until { resolver.count == 2 })
    }

    @Test("作废后回到乐观值并重新探测")
    func invalidateForcesRefresh() async throws {
        let resolver = ResolverRecorder(result: resolution(canOpen: false, canReveal: false))
        let cache = PanelFileCapabilityCache(
            ttl: 60,
            notificationCenter: nil,
            resolver: resolver.resolve
        )
        let request = makeRequest(kind: .file)
        let resolved = FileCapabilities(canOpen: false, canReveal: false)

        _ = cache.capabilities(for: request)
        #expect(await Wait.until { cache.cachedCapabilities(for: request.itemID) == resolved })

        cache.invalidateAll()
        #expect(cache.cachedCapabilities(for: request.itemID) == nil)
        #expect(cache.capabilities(for: request) == FileCapabilities(canOpen: true, canReveal: true))
        #expect(await Wait.until { resolver.count == 2 })
    }

    @Test("探测出的过期 bookmark 交回回写口")
    func deliversRefreshedBookmarks() async throws {
        let refresh = RefreshedBookmark(pathKey: "a", data: Data([1, 2, 3]))
        let resolver = ResolverRecorder(result: FileCapabilityResolution(
            capabilities: FileCapabilities(canOpen: true, canReveal: true),
            refreshedBookmarks: [refresh]
        ))
        let received = BookmarkBox()
        let cache = PanelFileCapabilityCache(
            ttl: 60,
            notificationCenter: nil,
            resolver: resolver.resolve,
            onBookmarksRefreshed: { id, refreshes in received.record(id: id, refreshes: refreshes) }
        )
        let request = makeRequest(kind: .file)

        _ = cache.capabilities(for: request)
        #expect(await Wait.until { received.itemID == request.itemID })
        #expect(received.refreshes == [refresh])
    }

    @Test("乐观值按类型给出：没有路径的文件/图片不会被误放行")
    func optimisticValuesByKind() {
        #expect(optimistic(kind: .file, paths: ["/a"])
            == FileCapabilities(canOpen: true, canReveal: true))
        #expect(optimistic(kind: .file) == .none)
        #expect(optimistic(kind: .image) == .none)
        #expect(optimistic(kind: .image, hasInlineImage: true)
            == FileCapabilities(canOpen: true, canReveal: false))
        #expect(optimistic(kind: .text, hasText: true)
            == FileCapabilities(canOpen: true, canReveal: false))
        #expect(optimistic(kind: .link, isOpenableLink: true)
            == FileCapabilities(canOpen: true, canReveal: false))
        #expect(optimistic(kind: .color) == .none)
    }

    // MARK: - 夹具

    private func optimistic(
        kind: ClipboardItemKind,
        paths: [String] = [],
        hasInlineImage: Bool = false,
        hasText: Bool = false,
        isOpenableLink: Bool = false
    ) -> FileCapabilities {
        PanelFileCapabilityCache.optimistic(for: makeRequest(
            kind: kind,
            paths: paths,
            hasInlineImage: hasInlineImage,
            hasText: hasText,
            isOpenableLink: isOpenableLink
        ))
    }

    private func resolution(canOpen: Bool, canReveal: Bool) -> FileCapabilityResolution {
        FileCapabilityResolution(
            capabilities: FileCapabilities(canOpen: canOpen, canReveal: canReveal),
            refreshedBookmarks: []
        )
    }

    private func makeRequest(
        kind: ClipboardItemKind,
        paths: [String] = ["/tmp/sixone-capability"],
        hasInlineImage: Bool = false,
        hasText: Bool = false,
        isOpenableLink: Bool = false
    ) -> FileCapabilityRequest {
        FileCapabilityRequest(
            itemID: UUID(),
            recencyID: UUID(),
            kind: kind,
            paths: paths,
            bookmark: nil,
            bookmarks: nil,
            hasInlineImage: hasInlineImage,
            hasText: hasText,
            isOpenableLink: isOpenableLink
        )
    }
}

private nonisolated final class ResolverRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: FileCapabilityResolution
    private var storedCount = 0

    init(result: FileCapabilityResolution) {
        storedResult = result
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCount
    }

    func resolve(_ request: FileCapabilityRequest) -> FileCapabilityResolution {
        lock.lock()
        defer { lock.unlock() }
        storedCount += 1
        return storedResult
    }
}

@MainActor
private final class TestClock {
    var date = Date(timeIntervalSince1970: 1_000)
}

@MainActor
private final class BookmarkBox {
    var itemID: UUID?
    var refreshes: [RefreshedBookmark] = []

    func record(id: UUID, refreshes: [RefreshedBookmark]) {
        itemID = id
        self.refreshes = refreshes
    }
}
