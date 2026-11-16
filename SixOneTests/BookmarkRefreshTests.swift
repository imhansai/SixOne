//
//  BookmarkRefreshTests.swift
//  SixOneTests
//  过期 security-scoped bookmark 的刷新回写。

import Foundation
import Testing
@testable import SixOne

@Suite("过期 bookmark 的刷新回写")
@MainActor
struct BookmarkRefreshTests {
    @Test("单文件改名：解析返回重取 bookmark 并写回条目")
    func staleSingleBookmarkIsRefreshed() throws {
        let harness = try ClipboardHarness()
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-stale-single")
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("原名.txt")
        try Data("hi".utf8).write(to: original)
        let originalBookmark = try #require(
            SecurityScopedFileAccess.payload(forPaths: [original.path]).bookmark
        )
        let item = ClipboardItem(kind: .file, filePath: original.path)
        item.securityScopeBookmark = originalBookmark
        harness.context.insert(item)
        try harness.context.save()

        let renamed = directory.appendingPathComponent("改名.txt")
        try FileManager.default.moveItem(at: original, to: renamed)

        let urls = harness.manager.resolvedFileURLs(for: item)
        #expect(urls.compactMap { $0 }.first?.resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path)

        let stored = try #require(item.securityScopeBookmark)
        #expect(stored != originalBookmark)

        // 重取的 bookmark 自身不再是 stale，直接解析到改名后的位置。
        let resolved = try #require(
            SecurityScopedFileAccess.resolvedFileWithoutAccess(
                bookmark: item.securityScopeBookmark,
                path: item.filePath
            )
        )
        #expect(resolved.refreshedBookmark == nil)
        #expect(resolved.url.resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path)
    }

    @Test("文件组内改名：只刷新对应路径键")
    func staleGroupBookmarkRefreshesOnlyItsKey() throws {
        let harness = try ClipboardHarness()
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-stale-group")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("a.txt")
        let second = directory.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: first)
        try Data("b".utf8).write(to: second)
        let bookmarks = try #require(
            SecurityScopedFileAccess.payload(forPaths: [first.path, second.path]).bookmarks
        )
        let originalMap = SecurityScopedFileAccess.decodeBookmarks(bookmarks)

        let item = ClipboardItem(kind: .file, filePaths: [first.path, second.path])
        item.securityScopeBookmarks = bookmarks
        harness.context.insert(item)
        try harness.context.save()

        let renamed = directory.appendingPathComponent("a-改.txt")
        try FileManager.default.moveItem(at: first, to: renamed)

        _ = harness.manager.resolvedFileURLs(for: item)

        let storedMap = SecurityScopedFileAccess.decodeBookmarks(item.securityScopeBookmarks)
        #expect(storedMap[first.path] != originalMap[first.path])
        #expect(storedMap[second.path] == originalMap[second.path])
    }

    @Test("同一会话再次过期：只解析，不再重复回写")
    func refreshHappensOncePerSession() throws {
        let harness = try ClipboardHarness()
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-stale-once")
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("原名.txt")
        try Data("hi".utf8).write(to: original)
        let bookmark = try #require(
            SecurityScopedFileAccess.payload(forPaths: [original.path]).bookmark
        )
        let item = ClipboardItem(kind: .file, filePath: original.path)
        item.securityScopeBookmark = bookmark
        harness.context.insert(item)
        try harness.context.save()

        let renamed = directory.appendingPathComponent("改名.txt")
        try FileManager.default.moveItem(at: original, to: renamed)
        _ = harness.manager.resolvedFileURLs(for: item)
        let firstStored = try #require(item.securityScopeBookmark)
        #expect(firstStored != bookmark)

        let movedAgain = directory.appendingPathComponent("再改名.txt")
        try FileManager.default.moveItem(at: renamed, to: movedAgain)
        let urls = harness.manager.resolvedFileURLs(for: item)
        #expect(urls.compactMap { $0 }.first?.resolvingSymlinksInPath().path == movedAgain.resolvingSymlinksInPath().path)
        #expect(item.securityScopeBookmark == firstStored)
    }

    @Test("文件未移动：bookmark 原样保留")
    func freshBookmarkIsNotRewritten() throws {
        let harness = try ClipboardHarness()
        let file = try TemporaryFiles.makeFile(prefix: "sixone-stale-fresh", contents: "hi")
        defer { try? FileManager.default.removeItem(at: file) }
        let bookmark = try #require(
            SecurityScopedFileAccess.payload(forPaths: [file.path]).bookmark
        )
        let item = ClipboardItem(kind: .file, filePath: file.path)
        item.securityScopeBookmark = bookmark
        harness.context.insert(item)
        try harness.context.save()

        _ = harness.manager.resolvedFileURLs(for: item)

        #expect(item.securityScopeBookmark == bookmark)
    }
}
