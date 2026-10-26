//
//  PreviewLauncherTests.swift
//  SixOneTests

import Foundation
import SwiftData
import Testing
@testable import SixOne

@Suite("打开预览的校验")
@MainActor
struct PreviewLauncherTests {
    @Test("文本条目直接可预览")
    func presentsTextItem() throws {
        let harness = try Harness()
        let item = ClipboardItem(kind: .text, text: "内容")

        #expect(harness.launcher.present(item))
        #expect(harness.previewState.item === item)
    }

    @Test("图片条目也按 bookmark 找回源文件的新位置")
    func imageSourceFollowsBookmark() throws {
        let harness = try Harness()
        defer { harness.previewState.close() }
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-image-preview")
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("原名.png")
        try Data([0x00]).write(to: original)
        let bookmark = try #require(
            SecurityScopedFileAccess.payload(forPaths: [original.path]).bookmark
        )

        let item = ClipboardItem(
            kind: .image,
            imageData: Data([0x00]),
            filePath: original.path,
            contentType: "PNG"
        )
        item.securityScopeBookmark = bookmark
        let renamed = directory.appendingPathComponent("改名.png")
        try FileManager.default.moveItem(at: original, to: renamed)

        #expect(harness.launcher.present(item))
        let scoped = try #require(harness.previewState.scopedFileURL)
        #expect(scoped.url.lastPathComponent == "改名.png", "没按 bookmark 解析到改名后的文件")
        // 临时目录解析后会带 /private 前缀，比较前统一解开符号链接。
        #expect(
            scoped.url.resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path,
            "解析出的路径不是改名后的位置：\(scoped.url.path)"
        )
    }

    @Test("图片源文件不在时，位图仍可预览")
    func imagePreviewDoesNotRequireSourceFile() throws {
        let harness = try Harness()
        let item = ClipboardItem(
            kind: .image,
            imageData: Data([0x00]),
            filePath: "/definitely/not/here-\(UUID().uuidString).png",
            contentType: "PNG"
        )

        #expect(harness.launcher.present(item))
        #expect(harness.previewState.scopedFileURL == nil)
    }

    @Test("文件不存在时拒绝预览并弹提示")
    func rejectsMissingFile() throws {
        let harness = try Harness()
        let item = ClipboardItem(kind: .file, filePath: "/definitely/not/here-\(UUID().uuidString).txt")

        #expect(!harness.launcher.present(item))
        #expect(harness.previewState.item == nil)
        #expect(harness.noticeState.message != nil)
    }

    @Test("打开失败不影响已经开着的预览")
    func failureKeepsCurrentPreview() throws {
        let harness = try Harness()
        let textItem = ClipboardItem(kind: .text, text: "已经打开的")
        #expect(harness.launcher.present(textItem))

        let missingFile = ClipboardItem(kind: .file, filePath: "/definitely/not/here.txt")
        #expect(!harness.launcher.present(missingFile))
        #expect(harness.previewState.item === textItem)
    }

    @Test("按 id 打开：同一条不重复打开")
    func skipsAlreadyPresentedItem() throws {
        let harness = try Harness()
        let item = ClipboardItem(kind: .text, text: "内容")
        #expect(harness.launcher.present(item))

        #expect(!harness.launcher.presentIfPossible(id: item.id))
    }

    @Test("按 id 打开：库里取不到整条时不动状态")
    func skipsUnknownItem() throws {
        let harness = try Harness()

        #expect(!harness.launcher.presentIfPossible(id: UUID()))
        #expect(harness.previewState.item == nil)
    }

    @Test("预览间切换：多文件组不进入，只提示从列表打开")
    func rejectsFileGroupDuringPreviewNavigation() throws {
        let harness = try Harness()
        let textItem = ClipboardItem(kind: .text, text: "已经打开的")
        #expect(harness.launcher.present(textItem))

        let group = ClipboardItem(kind: .file, filePaths: ["/tmp/a.txt", "/tmp/b.txt"])
        harness.container.mainContext.insert(group)
        try harness.container.mainContext.save()

        #expect(!harness.launcher.presentIfPossible(id: group.id))
        #expect(harness.previewState.item === textItem, "当前预览不能被换掉")
        #expect(harness.noticeState.message != nil, "要告诉用户从列表打开")
    }

    private struct Harness {
        let container: ModelContainer
        let previewState = PreviewState()
        let noticeState = NoticeState()
        let launcher: PreviewLauncher

        init() throws {
            let schema = Schema([ClipboardItem.self])
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            let manager = ClipboardManager(
                container: container,
                settings: SettingsStore(storage: InMemorySettingsStorage()),
                events: ClipboardHistoryEventBus(),
                previewCache: PanelCaches().preview
            )
            launcher = PreviewLauncher(
                manager: manager,
                previewState: previewState,
                noticeState: noticeState
            )
        }
    }
}
