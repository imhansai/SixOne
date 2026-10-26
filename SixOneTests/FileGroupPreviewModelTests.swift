//
//  FileGroupPreviewModelTests.swift
//  SixOneTests

import Foundation
import Testing
@testable import SixOne

@Suite("文件组行与预览方式判定")
struct FileGroupPreviewModelTests {
    @Test("有解析结果时显示当前文件名")
    func prefersResolvedName() {
        let entry = GroupFileEntry(
            index: 1,
            path: "/old/原名.png",
            url: URL(fileURLWithPath: "/new/新名.png")
        )
        #expect(entry.id == 1)
        #expect(entry.name == "新名.png")
    }

    @Test("失联时回落到捕获时的路径")
    func fallsBackToCapturedPath() {
        let entry = GroupFileEntry(index: 0, path: "/old/原名.png", url: nil)
        #expect(entry.name == "原名.png")
    }

    @Test("按类型与扩展名选渲染器", arguments: [
        ("a.png", FilePreviewKind.image),
        ("a.heic", FilePreviewKind.image),
        ("a.gif", FilePreviewKind.quickLook),
        ("a.GIF", FilePreviewKind.quickLook),
        ("a.mov", FilePreviewKind.quickLook),
        ("a.mkv", FilePreviewKind.quickLook),
        ("a.pdf", FilePreviewKind.pdf),
        ("a.html", FilePreviewKind.html),
        ("a.txt", FilePreviewKind.text),
        ("a.rtf", FilePreviewKind.quickLook),
        ("a.zip", FilePreviewKind.quickLook),
        ("无扩展名", FilePreviewKind.text),
    ])
    func previewKind(fileName: String, expected: FilePreviewKind) {
        #expect(FilePreviewKind.of(URL(fileURLWithPath: "/tmp/\(fileName)")) == expected)
    }

    @Test("按类型与扩展名认影片", arguments: [
        ("a.mov", true),
        ("a.mp4", true),
        ("a.MKV", true),
        ("a.webm", true),
        ("a.png", false),
        ("a.txt", false),
        ("a.pdf", false),
        ("无扩展名", false),
    ])
    func isMovie(fileName: String, expected: Bool) {
        #expect(FilePreviewKind.isMovie(URL(fileURLWithPath: "/tmp/\(fileName)")) == expected)
    }
}
