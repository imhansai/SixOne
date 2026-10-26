//
//  PasteboardEntryParser.swift
//  SixOne
//
//  剪贴板变化 → 待入库记录；解析与 bookmark 固化放后台（NSPasteboardItem 不能离开主线程）。
//

import AppKit
import Foundation

enum PasteboardEntryParser {
    /// 一次复制解析出的载荷；`nonisolated` 因解析在后台线程。
    nonisolated struct Entry: Sendable {
        let kind: ClipboardItemKind
        let text: String?
        let attributedTextData: Data?
        let imageData: Data?
        /// 多文件为全部（捕获顺序），单文件/图片一条。
        let filePaths: [String]
        let contentType: String?
        /// 颜色条目的 NSColor 归档本体；非颜色为 nil。
        let colorData: Data?

        init(
            kind: ClipboardItemKind,
            text: String? = nil,
            attributedTextData: Data? = nil,
            imageData: Data? = nil,
            filePaths: [String] = [],
            contentType: String? = nil,
            colorData: Data? = nil
        ) {
            self.kind = kind
            self.text = text
            self.attributedTextData = attributedTextData
            self.imageData = imageData
            self.filePaths = filePaths
            self.contentType = contentType
            self.colorData = colorData
        }

        var filePath: String? { filePaths.first }

        /// 多文件列：只有 2 个以上文件才落这一列。
        var groupedFilePaths: [String]? { filePaths.count > 1 ? filePaths : nil }

        var contentKey: String {
            ClipboardItem.contentKey(
                kind: kind,
                text: text,
                imageData: imageData,
                filePaths: filePaths,
                colorData: colorData
            )
        }
    }

    /// 后台解析成品：内容载荷 + 已固化的文件访问权。
    nonisolated struct PreparedCapture: Sendable {
        let entry: Entry
        let fileAccess: SecurityScopedFileAccess.BookmarkPayload
    }

    /// 后台入口：解析并固化 bookmark（两步都可能很贵，且不碰库与界面）。
    nonisolated static func prepare(from snapshot: PasteboardSnapshot) -> PreparedCapture? {
        guard let entry = makeEntry(from: snapshot) else { return nil }
        return PreparedCapture(entry: entry, fileAccess: SecurityScopedFileAccess.payload(forPaths: entry.filePaths))
    }

    /// 解析一次复制；多文件须先收集全部 URL 再分类，否则首个文件的文件名文本会使其误判为文本。
    nonisolated static func makeEntry(from snapshot: PasteboardSnapshot) -> Entry? {
        // 保留 item 顺序即用户选择顺序。
        let fileItems: [(index: Int, url: URL)] = snapshot.items.enumerated().compactMap { index, item in
            guard let value = item.string(.fileURL),
                  let url = URL(string: value), url.isFileURL else { return nil }
            return (index, url)
        }

        if fileItems.count > 1 {
            return Entry(kind: .file, filePaths: fileItems.map(\.url.path))
        }

        guard let primary = snapshot.items.first else { return nil }

        // 图片文件仍按图片收；位图在带 file URL 的那一项上，未必是首个 item。
        if let fileItem = fileItems.first {
            let source = snapshot.items[fileItem.index]
            if let imageResult = imageResult(from: source, fileURL: fileItem.url) {
                return Entry(
                    kind: .image,
                    imageData: imageResult.data,
                    filePaths: [fileItem.url.path],
                    contentType: imageResult.contentType
                )
            }
            return Entry(kind: .file, filePaths: [fileItem.url.path])
        }

        // 链接须先于文本判定：Safari 写 .URL+.string，Chrome 地址栏只写 .string。
        if let linkEntry = linkEntry(from: primary) {
            return linkEntry
        }

        if let pngData = primary.data(.png),
           PasteboardFormat.isBitmap(pngData) {
            return Entry(kind: .image, imageData: pngData, contentType: "PNG")
        }
        if let tiffData = primary.data(.tiff),
           PasteboardFormat.isBitmap(tiffData) {
            return Entry(kind: .image, imageData: tiffData, contentType: "TIFF")
        }
        // 颜色类型是 NSColor 归档，统一剥成归档本体。
        if let raw = primary.data(.color), let colorData = PasteboardFormat.colorArchive(from: raw) {
            return Entry(kind: .color, colorData: colorData)
        }
        // hex 文本颜色也归档进 colorData，原文留在 text 供写回。
        if let text = primary.string(.string),
           let color = hexColor(from: text),
           let colorData = PasteboardFormat.colorData(of: color) {
            return Entry(kind: .color, text: text, colorData: colorData)
        }
        if let text = primary.string(.string) {
            let attributed = attributedTextData(from: primary)
            if attributed == nil, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil
            }
            return Entry(kind: .text, text: text, attributedTextData: attributed)
        }
        return nil
    }

    /// 从单个 item 判定链接：`.URL` 任意 scheme，或整段纯文本是 http/https 链接。
    private nonisolated static func linkEntry(from item: PasteboardSnapshot.Item) -> Entry? {
        // .URL 明确声明是链接，任意 scheme 都认。
        if let raw = item.string(.URL),
           let url = URL(string: raw), url.scheme != nil {
            return Entry(kind: .link, text: raw)
        }
        if let raw = item.string(.string),
           let urlString = bareHTTPURL(in: raw) {
            return Entry(kind: .link, text: urlString)
        }
        return nil
    }

    /// 整段纯文本恰是 http/https 链接时返回它；带额外文字算普通文本。
    private nonisolated static func bareHTTPURL(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ !$0.isWhitespace }),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return trimmed
    }

    /// 整段纯文本若是 hex 颜色则解析；裸写法要求含数字，避免把 "facade" 这类单词吃成颜色。
    private nonisolated static func hexColor(from text: String) -> NSColor? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits: String
        if trimmed.hasPrefix("#") {
            digits = String(trimmed.dropFirst())
        } else {
            guard trimmed.contains(where: \.isNumber) else { return nil }
            digits = trimmed
        }
        guard digits.count == 6,
              digits.allSatisfy(\.isHexDigit),
              let value = UInt64(digits, radix: 16) else { return nil }
        let r = CGFloat(Int((value >> 16) & 0xFF)) / 255
        let g = CGFloat(Int((value >> 8) & 0xFF)) / 255
        let b = CGFloat(Int(value & 0xFF)) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// 富文本统一以 RTF 返回；无格式为 nil。
    private nonisolated static func attributedTextData(from item: PasteboardSnapshot.Item) -> Data? {
        if let rtf = item.data(.rtf),
           NSAttributedString(rtf: rtf, documentAttributes: nil) != nil {
            return rtf
        }
        if let html = item.data(.html),
           let attr = NSAttributedString(html: html, options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil),
           let data = try? attr.data(
               from: NSRange(location: 0, length: attr.length),
               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
           ) {
            return data
        }
        return nil
    }

    /// 原始图像数据与类型。
    private nonisolated static func imageResult(
        from item: PasteboardSnapshot.Item,
        fileURL: URL
    ) -> (data: Data, contentType: String)? {
        let ext = fileURL.pathExtension.lowercased()
        guard PasteboardFormat.imageFileExtensions.contains(ext) else { return nil }

        var typeOrder: [NSPasteboard.PasteboardType] = [
            PasteboardFormat.pasteboardType(forContentType: ext.uppercased())
        ]
        if !typeOrder.contains(.png) { typeOrder.append(.png) }
        if !typeOrder.contains(.tiff) { typeOrder.append(.tiff) }

        for type in typeOrder {
            guard let data = item.data(type),
                  PasteboardFormat.isBitmap(data) else { continue }
            let contentType = (type == .tiff) ? "TIFF" : "PNG"
            return (data, contentType)
        }
        return nil
    }
}
