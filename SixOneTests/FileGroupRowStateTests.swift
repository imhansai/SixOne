//
//  FileGroupRowStateTests.swift
//  SixOneTests

import Foundation
import Testing
@testable import SixOne

@Suite("文件组行状态")
@MainActor
struct FileGroupRowStateTests {
    @Test("文件读取大小与目录标记")
    func fileMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixone-row-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("a.txt")
        try Data("hello".utf8).write(to: url)

        let state = FileGroupRowState()
        await state.load(
            file: GroupFileEntry(index: 0, path: url.path, url: url),
            cache: FileGroupThumbnailCache(),
            displayScale: 1
        )

        #expect(state.isDirectory == false)
        #expect(state.size == 5)
    }

    @Test("目录不取缩略图")
    func directorySkipsThumbnail() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixone-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let state = FileGroupRowState()
        await state.load(
            file: GroupFileEntry(index: 0, path: url.path, url: url),
            cache: FileGroupThumbnailCache(),
            displayScale: 1
        )

        #expect(state.isDirectory)
        #expect(state.thumbnail == nil)
    }

    @Test("失联路径保留空状态")
    func missingPath() async {
        let state = FileGroupRowState()
        await state.load(
            file: GroupFileEntry(index: 0, path: "/tmp/sixone-missing-\(UUID().uuidString)", url: nil),
            cache: FileGroupThumbnailCache(),
            displayScale: 1
        )

        #expect(state.isDirectory == false)
        #expect(state.size == nil)
        #expect(state.thumbnail == nil)
    }
}
