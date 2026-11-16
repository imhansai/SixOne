//
//  TextFileReader.swift
//  SixOne

import CoreFoundation
import Foundation

nonisolated struct TextFileContent: Sendable {
    let text: String
    let isTruncated: Bool
    let totalBytes: Int64

    /// 解码后仍超过渲染上限，视图会再按字符截断。
    var isCharacterTruncated: Bool {
        TextPreviewLimit.exceeds(plainText: text, attributedTextData: nil)
    }
}

/// 文本文件读取：编码兜底，超过上限只读开头。
nonisolated enum TextFileReader {
    /// 单次最多读入的字节数；与预览渲染上限一致。
    static let maxReadBytes = TextPreviewLimit.maxUTF8Bytes

    /// 异步读取正文与截断信息；失败返回 nil。
    static func content(at url: URL) async -> TextFileContent? {
        let work = Task.detached(priority: .userInitiated) { read(at: url) }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private static func read(at url: URL) -> TextFileContent? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile != false,
              let fileSize = values.fileSize,
              let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        var data = Data()
        do {
            // 最多读上限 + 1：stat 后文件增长也不会撑爆内存。
            while data.count <= maxReadBytes {
                guard !Task.isCancelled else { return nil }
                guard let chunk = try handle.read(upToCount: maxReadBytes + 1 - data.count),
                      !chunk.isEmpty else { break }
                data.append(chunk)
            }
        } catch {
            return nil
        }
        // 声称非空却读不到字节：视为不可读。
        guard !data.isEmpty || fileSize == 0 else { return nil }

        // EOF 时以实际字节为准：stat 后文件可能被截短。
        let reachedEOF = data.count <= maxReadBytes
        let total = reachedEOF ? Int64(data.count) : max(Int64(fileSize), Int64(data.count))
        let truncated = !reachedEOF
        let payload = data.prefix(maxReadBytes)
        guard let text = decode(payload, truncated: truncated) else { return nil }
        return TextFileContent(text: text, isTruncated: truncated, totalBytes: total)
    }

    /// BOM → UTF-8 → GB18030 → Latin-1。
    private static func decode(_ data: Data, truncated: Bool) -> String? {
        if data.isEmpty { return "" }
        guard !Task.isCancelled else { return nil }

        if data.starts(with: utf8BOM) {
            return decodePrefix(
                Data(data.dropFirst(utf8BOM.count)),
                encoding: .utf8,
                allowTrim: truncated
            )
        }
        // UTF-16 含 NUL，须先于 NUL 判定。
        if data.starts(with: utf16LittleEndianBOM) || data.starts(with: utf16BigEndianBOM) {
            return decodeUTF16(data, truncated: truncated)
        }
        // 含 NUL 视为二进制。
        guard !containsNUL(data) else { return nil }

        if let text = decodePrefix(data, encoding: .utf8, allowTrim: truncated) { return text }
        guard !Task.isCancelled else { return nil }
        if let text = decodePrefix(data, encoding: gb18030, allowTrim: truncated) { return text }
        guard !Task.isCancelled else { return nil }
        return String(data: data, encoding: .isoLatin1)
    }

    /// 截断可能停在多字节序列中间：末尾最多丢 3 字节。
    private static func decodePrefix(
        _ data: Data,
        encoding: String.Encoding,
        allowTrim: Bool
    ) -> String? {
        if let text = String(data: data, encoding: encoding) { return text }
        guard allowTrim, !data.isEmpty else { return nil }
        for drop in 1...min(3, data.count) {
            let prefix = Data(data.dropLast(drop))
            if prefix.isEmpty { return "" }
            if let text = String(data: prefix, encoding: encoding) { return text }
        }
        return nil
    }

    /// UTF-16 按 BOM 解；截断切断代理对时再退一个码元。
    private static func decodeUTF16(_ data: Data, truncated: Bool) -> String? {
        let evenCount = data.count - data.count % 2
        let usable = Data(data.prefix(evenCount))
        if let text = String(data: usable, encoding: .utf16) { return text }
        guard truncated, usable.count >= 2 else { return nil }
        return String(data: Data(usable.dropLast(2)), encoding: .utf16)
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
