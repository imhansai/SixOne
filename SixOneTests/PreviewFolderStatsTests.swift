//
//  PreviewFolderStatsTests.swift
//  SixOneTests
//  文件夹预览副标题：访达式的递归大小与项目数。
//

import Foundation
import Testing
@testable import SixOne

@Suite("文件夹元数据")
struct PreviewFolderStatsTests {
    @Test("递归统计子目录里的普通文件大小，目录本身只计数")
    func scansNestedContents() async throws {
        let root = try TemporaryFiles.makeDirectory(prefix: "sixone-folder")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0, count: 10).write(to: root.appendingPathComponent("a.bin"))
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 20).write(to: sub.appendingPathComponent("b.bin"))

        let stats = try #require(await PreviewMetadataModel.computeFolderStats(at: root))
        #expect(stats.totalSize == 30)
        #expect(stats.itemCount == 3)
    }

    @Test("空目录为 0 字节、0 个项目")
    func emptyFolder() async throws {
        let root = try TemporaryFiles.makeDirectory(prefix: "sixone-folder")
        defer { try? FileManager.default.removeItem(at: root) }

        let stats = try #require(await PreviewMetadataModel.computeFolderStats(at: root))
        #expect(stats == FolderStats(totalSize: 0, itemCount: 0))
    }
}

@Suite("文件夹预览副标题")
@MainActor
struct PreviewFolderSubtitleTests {
    private var folderMeta: PreviewFileMeta {
        PreviewFileMeta(size: nil, modDate: nil, isDirectory: true)
    }

    @Test("统计未完成时回落到「文件夹」")
    func pendingShowsFolder() {
        #expect(PreviewSubtitle.fileStats(folderMeta, folderStats: nil) == Localizer.string("Folder"))
    }

    @Test("统计完成后显示「大小 · n 个项目」")
    func showsSizeAndItemCount() {
        let countText = String(
            format: Localizer.string("%@ items"),
            PreviewSubtitle.groupedCount(42)
        )
        let expected = "\(ByteCountFormatting.string(fromByteCount: 3_000)) · \(countText)"
        #expect(
            PreviewSubtitle.fileStats(
                folderMeta,
                folderStats: FolderStats(totalSize: 3_000, itemCount: 42)
            ) == expected
        )
    }

    @Test("普通文件仍只显示大小")
    func regularFileShowsSize() {
        let meta = PreviewFileMeta(size: 1_024, modDate: nil, isDirectory: false)
        #expect(
            PreviewSubtitle.fileStats(meta, folderStats: nil)
                == ByteCountFormatting.string(fromByteCount: 1_024)
        )
    }
}
