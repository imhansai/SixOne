//
//  PanelCachesTests.swift
//  SixOneTests
//  注入式缓存：命中与失效的语义。

import Foundation
import Testing
@testable import SixOne

@Suite("面板缓存")
@MainActor
struct PanelCachesTests {
    @Test("路径判定区分文件、文件夹与不存在")
    func classifiesPaths() throws {
        let cache = PanelCaches().query
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-cache")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)

        #expect(cache.fileKind(atPath: directory.path) == .folder)
        #expect(cache.fileKind(atPath: file.path) == .file)
        #expect(cache.fileKind(atPath: directory.appendingPathComponent("没有这个").path) == .missing)
    }

    @Test("同路径的判定被缓存：文件删掉后不会再翻新（滚动期不反复打文件系统的取舍）")
    func fileKindIsCachedOnPurpose() throws {
        let cache = PanelCaches().query
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-cache")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("b.txt")
        try Data("x".utf8).write(to: file)

        #expect(cache.fileKind(atPath: file.path) == .file)
        try FileManager.default.removeItem(at: file)
        #expect(cache.fileKind(atPath: file.path) == .file)
    }

    @Test("时间文案按条目 id + 时间值缓存：触达刷新时间后不复用旧文案")
    func timeCacheKeyFollowsActivity() {
        let cache = PanelCaches().time
        let id = UUID()
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now

        let today = cache.copyTime(for: id, lastActivityAt: now, locale: .current)
        #expect(cache.copyTime(for: id, lastActivityAt: now, locale: .current) == today)

        // 时间值变了应换新文案，复用旧值会立刻现形。
        let older = cache.copyTime(for: id, lastActivityAt: yesterday, locale: .current)
        #expect(older != today)
        #expect(cache.copyTime(for: id, lastActivityAt: yesterday, locale: .current) == older)
    }
}
