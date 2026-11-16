//
//  TextFileReaderTests.swift
//  SixOneTests

import CoreFoundation
import Foundation
import Testing
@testable import SixOne

/// 编码链 BOM → UTF-8 → GB18030 → Latin-1；含 NUL 的字节不算文本。
@Suite("文本文件读取")
struct TextFileReaderTests {
    @Test("空文件读出空串")
    func emptyFileReadsEmpty() async throws {
        let url = try TemporaryFiles.makeFile(prefix: "sixone-text", data: Data())
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await TextFileReader.content(at: url)?.text == "")
    }

    @Test("文件不存在时为 nil")
    func missingFileIsNil() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixone-missing-\(UUID().uuidString).txt")
        #expect(await TextFileReader.content(at: url) == nil)
    }

    @Test("UTF-8 原文读得出；带 BOM 时 BOM 不留在正文里")
    func utf8PlainAndBOM() async throws {
        let plain = try TemporaryFiles.makeFile(prefix: "sixone-text", data: Data("中文正文".utf8))
        defer { try? FileManager.default.removeItem(at: plain) }
        #expect(await TextFileReader.content(at: plain)?.text == "中文正文")

        var withBOMData = Data([0xEF, 0xBB, 0xBF])
        withBOMData.append(Data("带 BOM".utf8))
        let withBOM = try TemporaryFiles.makeFile(prefix: "sixone-text", data: withBOMData)
        defer { try? FileManager.default.removeItem(at: withBOM) }
        #expect(await TextFileReader.content(at: withBOM)?.text == "带 BOM")
    }

    @Test("UTF-16 按 BOM 解")
    func utf16BOM() async throws {
        var data = Data([0xFF, 0xFE])
        data.append("hello".data(using: .utf16LittleEndian) ?? Data())
        let url = try TemporaryFiles.makeFile(prefix: "sixone-text", data: data)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await TextFileReader.content(at: url)?.text == "hello")
    }

    @Test("GB18030：非法 UTF-8 的中文旧编码仍认得出")
    func gb18030Fallback() async throws {
        let url = try TemporaryFiles.makeFile(prefix: "sixone-text", data: Data([0xD6, 0xD0, 0xCE, 0xC4]))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await TextFileReader.content(at: url)?.text == "中文")
    }

    @Test("含 NUL 的字节不是文本，不把二进制解成字符串")
    func rejectsNULBytes() async throws {
        let url = try TemporaryFiles.makeFile(prefix: "sixone-text", data: Data([0x61, 0x00, 0x62]))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await TextFileReader.content(at: url) == nil)
    }

    @Test("既非 UTF-8 也非 GB18030 的单字节序列回落到 Latin-1")
    func latin1Fallback() async throws {
        let url = try TemporaryFiles.makeFile(prefix: "sixone-text", data: Data([0xE9, 0x20]))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await TextFileReader.content(at: url)?.text == "é ")
    }

    @Test("超过读取上限：只读开头并报告总大小")
    func truncatesLargeFile() async throws {
        let data = Data(repeating: 0x61, count: TextFileReader.maxReadBytes + 1)
        let url = try TemporaryFiles.makeFile(prefix: "sixone-text-large", data: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try #require(await TextFileReader.content(at: url))
        #expect(content.isTruncated)
        #expect(content.totalBytes == Int64(data.count))
        #expect(content.text.utf8.count == TextFileReader.maxReadBytes)
    }

    @Test("上限切断多字节字符：丢掉不完整尾部，不产生替换字符")
    func truncationDropsPartialUTF8Sequence() async throws {
        var data = Data(repeating: 0x61, count: TextFileReader.maxReadBytes - 1)
        data.append("中".data(using: .utf8) ?? Data())
        data.append(Data(repeating: 0x62, count: 10))
        let url = try TemporaryFiles.makeFile(prefix: "sixone-text-split", data: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try #require(await TextFileReader.content(at: url))
        #expect(content.isTruncated)
        #expect(!content.text.contains("\u{FFFD}"))
        #expect(content.text.utf8.count == TextFileReader.maxReadBytes - 1)
    }

    @Test("解码后超过渲染上限：标记字符截断")
    func marksCharacterTruncation() async throws {
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        let text = String(repeating: "中", count: 1_400_000)
        let data = try #require(text.data(using: gb18030))
        let url = try TemporaryFiles.makeFile(prefix: "sixone-text-char-limit", data: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try #require(await TextFileReader.content(at: url))
        #expect(!content.isTruncated)
        #expect(content.isCharacterTruncated)
    }

    @Test("恰好等于上限：不标记截断")
    func exactlyAtLimitIsNotTruncated() async throws {
        let data = Data(repeating: 0x61, count: TextFileReader.maxReadBytes)
        let url = try TemporaryFiles.makeFile(prefix: "sixone-text-limit", data: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try #require(await TextFileReader.content(at: url))
        #expect(!content.isTruncated)
        #expect(content.totalBytes == Int64(data.count))
        #expect(content.text.utf8.count == data.count)
    }
}
