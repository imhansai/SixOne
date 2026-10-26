//
//  TextFileReader.swift
//  SixOne

import CoreFoundation
import Foundation

/// 把文本文件读成字符串并提供编码兜底；只负责内容，读不出返回 nil。
/// nonisolated：读盘与解码在后台执行。
nonisolated enum TextFileReader {
    /// 异步读取；调用方取消时一并取消后台任务，失败返回 nil。
    static func text(at url: URL) async -> String? {
        let work = Task.detached(priority: .userInitiated) { readText(at: url) }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private static func readText(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let text = decode(data)
        // 解码无法中断：取消后丢弃结果。
        return Task.isCancelled ? nil : text
    }

    /// 解码优先级：BOM → UTF-8 → GB18030 → 单字节兜底。
    private static func decode(_ data: Data) -> String? {
        if data.isEmpty { return "" }
        guard !Task.isCancelled else { return nil }

        if data.starts(with: utf8BOM) {
            return String(data: data.dropFirst(utf8BOM.count), encoding: .utf8)
        }
        // UTF-16 含 NUL，须先于 NUL 判定。
        if data.starts(with: utf16LittleEndianBOM) || data.starts(with: utf16BigEndianBOM) {
            return String(data: data, encoding: .utf16)
        }
        // 认识的编码都不含 NUL；含 NUL 视为二进制，也避免整份解码。
        guard !containsNUL(data) else { return nil }

        if let text = String(data: data, encoding: .utf8) { return text }
        guard !Task.isCancelled else { return nil }
        if let text = String(data: data, encoding: gb18030) { return text }
        guard !Task.isCancelled else { return nil }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func containsNUL(_ data: Data) -> Bool {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return false }
            return memchr(base, 0, buffer.count) != nil
        }
    }

    private static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let utf16LittleEndianBOM: [UInt8] = [0xFF, 0xFE]
    private static let utf16BigEndianBOM: [UInt8] = [0xFE, 0xFF]
}
