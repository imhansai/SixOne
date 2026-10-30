//
//  FileLocationTests.swift
//  SixOneTests
//  文件位置取值：文件名/路径拆分，以及哪些条目该显示。

import Foundation
import Testing
@testable import SixOne

@Suite("文件位置")
@MainActor
struct FileLocationTests {
    @Test("文件名与绝对路径从路径拆出")
    func splitsNameAndPath() throws {
        let location = try #require(FileLocation(path: "/Users/example/Downloads/六一.png"))
        #expect(location.name == "六一.png")
        #expect(location.path == "/Users/example/Downloads/六一.png")
    }

    @Test("保留路径里的空格与中文")
    func keepsSpacesAndNonASCII() throws {
        let path = "/Users/example/Desktop/设计稿 最终版.pdf"
        let location = try #require(FileLocation(path: path))
        #expect(location.name == "设计稿 最终版.pdf")
        #expect(location.path == path)
    }

    @Test("目录路径取最后一级目录名")
    func directoryPath() throws {
        let location = try #require(FileLocation(path: "/Users/example/Downloads/"))
        #expect(location.name == "Downloads")
        #expect(location.path == "/Users/example/Downloads")
    }

    @Test("从 URL 建位置")
    func fromURL() throws {
        let location = try #require(FileLocation(url: URL(fileURLWithPath: "/tmp/a b.png")))
        #expect(location.name == "a b.png")
        #expect(location.path == "/tmp/a b.png")
    }

    @Test("空路径不生成文件位置")
    func emptyPath() {
        #expect(FileLocation(path: nil) == nil)
        #expect(FileLocation(path: "") == nil)
        #expect(FileLocation(url: nil) == nil)
    }

    // MARK: - 文件位置取值

    @Test("没有源文件路径的条目不显示")
    func noSourcePath() {
        #expect(FileLocation.make(
            paths: [],
            scopedFileURL: nil,
            groupURLs: [],
            groupFileIndex: nil
        ) == nil)
    }

    @Test("没有解析结果时，图片回落到捕获路径")
    func imageSourceFallsBack() throws {
        let path = "/Users/example/Downloads/六一.png"
        let location = try #require(FileLocation.make(
            paths: [path],
            scopedFileURL: nil,
            groupURLs: [],
            groupFileIndex: nil
        ))
        #expect(location.name == "六一.png")
        #expect(location.path == path)
    }

    @Test("单文件优先用 bookmark 解析出的当前路径")
    func singleFileUsesScopedURL() throws {
        let scoped = URL(fileURLWithPath: "/new/新名.png")
        let location = try #require(FileLocation.make(
            paths: ["/old/旧名.png"],
            scopedFileURL: scoped,
            groupURLs: [],
            groupFileIndex: nil
        ))
        #expect(location.name == "新名.png")
        #expect(location.path == "/new/新名.png")
    }

    @Test("单文件没有解析结果时回落到捕获路径")
    func singleFileFallsBack() throws {
        let location = try #require(FileLocation.make(
            paths: ["/old/旧名.png"],
            scopedFileURL: nil,
            groupURLs: [],
            groupFileIndex: nil
        ))
        #expect(location.name == "旧名.png")
        #expect(location.path == "/old/旧名.png")
    }

    @Test("多文件组总览不显示")
    func groupOverviewHides() {
        let urls = [URL(fileURLWithPath: "/a/一.png"), URL(fileURLWithPath: "/a/二.png")]
        #expect(FileLocation.make(
            paths: ["/a/一.png", "/a/二.png"],
            scopedFileURL: nil,
            groupURLs: urls,
            groupFileIndex: nil
        ) == nil)
    }

    @Test("多文件组进入某一项时用解析后的当前路径")
    func groupItemUsesResolvedURL() throws {
        let urls = [URL(fileURLWithPath: "/a/一.png"), URL(fileURLWithPath: "/b/二改名.png")]
        let location = try #require(FileLocation.make(
            paths: ["/a/一.png", "/a/二.png"],
            scopedFileURL: nil,
            groupURLs: urls,
            groupFileIndex: 1
        ))
        #expect(location.name == "二改名.png")
        #expect(location.path == "/b/二改名.png")
    }

    @Test("多文件组失联项回落到捕获路径")
    func groupItemFallsBackWhenMissing() throws {
        let urls: [URL?] = [URL(fileURLWithPath: "/a/一.png"), nil]
        let location = try #require(FileLocation.make(
            paths: ["/a/一.png", "/a/二.png"],
            scopedFileURL: nil,
            groupURLs: urls,
            groupFileIndex: 1
        ))
        #expect(location.name == "二.png")
        #expect(location.path == "/a/二.png")
    }
}
