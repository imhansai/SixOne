//
//  ShareScopedURLAccessTests.swift
//  SixOneTests

import Foundation
import Testing
@testable import SixOne

@Suite("分享 URL 的安全作用域记账")
struct ShareScopedURLAccessTests {
    @Test("bookmark 解析成功：标记需要 stop")
    func bookmarkURLNeedsStop() throws {
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-share-scope")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.txt")
        try Data("hi".utf8).write(to: file)
        let bookmark = try #require(
            SecurityScopedFileAccess.payload(forPaths: [file.path]).bookmark
        )

        let scoped = try #require(
            SecurityScopedFileAccess.startScopedURL(bookmark: bookmark, path: file.path)
        )
        #expect(scoped.needsStop)
        scoped.url.stopAccessingSecurityScopedResource()
    }

    @Test("没有 bookmark：普通路径不欠 stop")
    func plainPathDoesNotNeedStop() throws {
        let file = try TemporaryFiles.makeFile(prefix: "sixone-share-scope", contents: "hi")
        defer { try? FileManager.default.removeItem(at: file) }

        let plain = try #require(
            SecurityScopedFileAccess.startScopedURL(bookmark: nil, path: file.path)
        )
        #expect(!plain.needsStop)
        #expect(plain.url.lastPathComponent == file.lastPathComponent)
    }

    @Test("文件组分享只返回仍可解析到的文件")
    func groupShareSkipsMissingFiles() throws {
        let file = try TemporaryFiles.makeFile(prefix: "sixone-share-group", contents: "hi")
        defer { try? FileManager.default.removeItem(at: file) }
        let item = ClipboardItem(
            kind: .file,
            filePaths: [file.path, "/definitely/not/here-\(UUID().uuidString).txt"]
        )

        let files = SecurityScopedFileAccess.startScopedURLsForSharing(for: item)
        #expect(files.count == 1)
        #expect(files.first?.url.lastPathComponent == file.lastPathComponent)
        #expect(files.allSatisfy { !$0.needsStop })
    }

    @Test("组内单文件分享只解析那一个")
    func singleGroupFileResolvesItsOwnPath() throws {
        let first = try TemporaryFiles.makeFile(prefix: "sixone-share-a", contents: "a")
        let second = try TemporaryFiles.makeFile(prefix: "sixone-share-b", contents: "b")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let item = ClipboardItem(kind: .file, filePaths: [first.path, second.path])

        let resolved = try #require(
            SecurityScopedFileAccess.startScopedURLForSharing(for: item, fileAt: 1)
        )
        #expect(resolved.url.lastPathComponent == second.lastPathComponent)
        #expect(!resolved.needsStop)
    }
}
