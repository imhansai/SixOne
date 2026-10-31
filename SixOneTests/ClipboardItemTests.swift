//
//  ClipboardItemTests.swift
//  SixOneTests

import AppKit
import Foundation
import Testing
@testable import SixOne

@Suite("条目路径与内容标识")
struct ClipboardItemTests {
    @Test("多文件只传 filePaths，filePath 收敛为首个文件")
    func groupPathsConvergeToFirst() {
        let item = ClipboardItem(kind: .file, filePaths: ["/tmp/a.txt", "/tmp/b.txt"])
        #expect(item.filePath == "/tmp/a.txt")
        #expect(item.filePaths == ["/tmp/a.txt", "/tmp/b.txt"])
        #expect(item.allFilePaths == ["/tmp/a.txt", "/tmp/b.txt"])
        #expect(item.fileCount == 2)
    }

    @Test("单文件只传 filePath，不落多文件列")
    func singlePathStaysSingle() {
        let item = ClipboardItem(kind: .file, filePath: "/tmp/only.txt")
        #expect(item.filePaths == nil)
        #expect(item.allFilePaths == ["/tmp/only.txt"])
        #expect(item.fileCount == 1)
    }

    @Test("非文件条目没有关联文件")
    func textItemHasNoFiles() {
        let item = ClipboardItem(kind: .text, text: "hello")
        #expect(item.allFilePaths.isEmpty)
        #expect(item.fileCount == 0)
    }

    @Test("同一批文件换序命中同一条")
    func contentKeyIgnoresOrder() {
        let key = { (paths: [String]) in
            ClipboardItem.contentKey(kind: .file, text: nil, imageData: nil, filePaths: paths)
        }
        #expect(key(["/tmp/a", "/tmp/b", "/tmp/c"]) == key(["/tmp/c", "/tmp/a", "/tmp/b"]))
    }

    @Test("少一个文件就是另一条")
    func contentKeyDistinguishesSubset() {
        let both = ClipboardItem.contentKey(kind: .file, text: nil, imageData: nil, filePaths: ["/tmp/a", "/tmp/b"])
        let one = ClipboardItem.contentKey(kind: .file, text: nil, imageData: nil, filePaths: ["/tmp/a"])
        #expect(both != one)
    }

    @Test("路径边界不会被拼成一串假重复")
    func contentKeyKeepsPathBoundaries() {
        let single = ClipboardItem.contentKey(kind: .file, text: nil, imageData: nil, filePaths: ["/tmp/ab"])
        let split = ClipboardItem.contentKey(kind: .file, text: nil, imageData: nil, filePaths: ["/tmp/a", "b"])
        #expect(single != split)
    }

    @Test("文本、图片、文件三类互不串键")
    func contentKeySeparatesKinds() {
        let text = ClipboardItem.contentKey(kind: .text, text: "x", imageData: nil, filePaths: [])
        let file = ClipboardItem.contentKey(kind: .file, text: nil, imageData: nil, filePaths: ["x"])
        let image = ClipboardItem.contentKey(kind: .image, text: nil, imageData: Data([0x01]), filePaths: [])
        #expect(Set([text, file, image]).count == 3)
    }

    @Test("图片去重 key 覆盖整段数据，首尾相同也不碰撞")
    func imageContentKeyUsesFullData() {
        var first = Data(repeating: 0, count: 200)
        var second = first
        first[100] = 1
        second[100] = 2

        let keyA = ClipboardItem.contentKey(kind: .image, text: nil, imageData: first, filePaths: [])
        let keyB = ClipboardItem.contentKey(kind: .image, text: nil, imageData: second, filePaths: [])

        #expect(keyA != keyB)
        #expect(ClipboardItem.currentContentKeyVersion == 2)
    }

    @Test("多文件条目的路径搜索快照包含组内每个文件")
    func searchSnapshotCoversEveryPath() {
        let item = ClipboardItem(kind: .file, filePaths: ["/tmp/报告.md", "/tmp/截图.png"])
        #expect(item.filePathsSearchText?.contains("报告.md") == true)
        #expect(item.filePathsSearchText?.contains("截图.png") == true)
    }

    @Test("多文件标题带上其余个数")
    func groupTitleMentionsRemainingCount() {
        let item = ClipboardItem(kind: .file, filePaths: ["/tmp/报告.md", "/tmp/b.png", "/tmp/c.png"])
        item.refreshTitleSnapshot()
        #expect(item.displayTitle.contains("报告.md"))
        #expect(item.displayTitle.contains("2"))
    }

    @Test("多文件标题按当前文案现算，不受旧快照影响")
    func groupTitleIgnoresStaleSnapshot() {
        let item = ClipboardItem(kind: .file, filePaths: ["/tmp/报告.md", "/tmp/b.png", "/tmp/c.png"])
        item.titleSnapshot = "旧文案"

        #expect(item.displayTitle != "旧文案")
        #expect(item.displayTitle.contains("报告.md"))
        #expect(item.displayTitle.contains("2"))
    }

    @Test("链接与颜色都有独立的去重键，且链接键跟随 URL 文本")
    func contentKeySeparatesLinkAndColor() {
        let linkA = ClipboardItem.contentKey(kind: .link, text: "https://a", imageData: nil, filePaths: [])
        let linkB = ClipboardItem.contentKey(kind: .link, text: "https://b", imageData: nil, filePaths: [])
        let colorA = ClipboardItem.contentKey(kind: .color, text: nil, imageData: nil, filePaths: [], colorData: Data([0x01]))
        let colorB = ClipboardItem.contentKey(kind: .color, text: nil, imageData: nil, filePaths: [], colorData: Data([0x02]))

        #expect(linkA != linkB)
        #expect(colorA != colorB)
        #expect(linkA != colorA)
        let text = ClipboardItem.contentKey(kind: .text, text: "https://a", imageData: nil, filePaths: [])
        #expect(linkA != text)
    }

    @Test("颜色标题是十六进制色值")
    func colorTitleIsHex() throws {
        let data = try #require(PasteboardFormat.colorData(of: NSColor(srgbRed: 0.5, green: 0.25, blue: 0, alpha: 1)))
        let item = ClipboardItem(kind: .color, colorData: data)

        #expect(item.colorHexString == "#804000")
    }

    @Test("半透明颜色的标题带上透明度（8 位十六进制），否则两行会看起来一样")
    func translucentColorTitleKeepsAlpha() throws {
        let opaque = try #require(PasteboardFormat.colorData(of: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)))
        let half = try #require(PasteboardFormat.colorData(of: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.5)))

        let opaqueItem = ClipboardItem(kind: .color, colorData: opaque)
        let halfItem = ClipboardItem(kind: .color, colorData: half)

        #expect(opaqueItem.displayTitle == "#3366CC")
        #expect(halfItem.displayTitle == "#3366CC80")
    }
}
