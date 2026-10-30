//
//  ClipboardPasteboardWriter.swift
//  SixOne
//
//  条目回写粘贴板：保持各类型原有的写回形态，并在写回后触达置顶。
//

import AppKit

final class ClipboardPasteboardWriter {
    private let pasteboard: PasteboardAccessing
    private let writer: ClipboardHistoryWriter
    private let fileAccess: ClipboardFileAccess

    /// 内部写回后同步捕获管道的 changeCount；装配后设置，避免轮询把内部拷贝当成新复制。
    var syncChangeCount: () -> Void = {}

    init(
        pasteboard: PasteboardAccessing,
        writer: ClipboardHistoryWriter,
        fileAccess: ClipboardFileAccess
    ) {
        self.pasteboard = pasteboard
        self.writer = writer
        self.fileAccess = fileAccess
    }

    // MARK: - 复制回粘贴板

    func copy(id: UUID) {
        guard let full = writer.fetchFullItem(id: id) else { return }
        copy(full)
    }

    func copy(_ item: ClipboardItem) {
        writeToPasteboard(item)
        syncChangeCount()
        writer.recordTouch(item)
    }

    /// 只写纯文本（颜色写十六进制色值），并触达置顶。
    func copyAsPlainText(id: UUID) {
        guard let full = writer.fetchFullItem(id: id) else { return }
        copyAsPlainText(full)
    }

    /// 只把关联的第 index 个文件写回剪贴板；解析不到时返回 false。
    @discardableResult
    func copy(_ item: ClipboardItem, fileAt index: Int) -> Bool {
        let urls = fileAccess.resolvedFileURLs(for: item)
        guard urls.indices.contains(index), let url = urls[index] else { return false }
        pasteboard.write(.fileURLs([url]))
        syncChangeCount()
        writer.recordTouch(item)
        return true
    }

    func copyAsPlainText(_ item: ClipboardItem) {
        pasteboard.write(.text(plainText(of: item) ?? "", rtf: nil))
        syncChangeCount()
        writer.recordTouch(item)
    }

    func copyPlainText(_ text: String) {
        pasteboard.write(.text(text, rtf: nil))
        syncChangeCount()
    }

    /// 条目的纯文本形态：正文优先，颜色用十六进制色值；必要时按 id 补齐。
    private func plainText(of item: ClipboardItem) -> String? {
        var text = item.text
        var colorData = item.colorData
        if text == nil || (item.kind == .color && colorData == nil),
           let full = writer.fetchFullItem(id: item.id) {
            text = full.text ?? text
            colorData = full.colorData ?? colorData
        }
        if let text, !text.isEmpty { return text }
        return colorData.flatMap(PasteboardFormat.hexString(ofColorData:))
    }

    func update(_ item: ClipboardItem) {
        // 内容变了，去重快照必须跟着变，否则再次复制命不中去重。
        item.refreshContentKey()
        writeToPasteboard(item)
        syncChangeCount()
        writer.recordTouch(item)
    }

    // MARK: - 写回形态

    private func writeToPasteboard(_ item: ClipboardItem) {
        switch item.kind {
        case .text:
            var attrData = item.attributedTextData
            var text = item.text
            // 列表查询排除了大字段，必要时按 id 补齐。
            if attrData == nil || text == nil, let full = writer.fetchFullItem(id: item.id) {
                attrData = full.attributedTextData ?? attrData
                text = full.text ?? text
            }
            pasteboard.write(.text(text ?? "", rtf: attrData))
        case .image:
            var data = item.imageData
            if data == nil, let full = writer.fetchFullItem(id: item.id) {
                data = full.imageData
            }
            let type = PasteboardFormat.pasteboardType(forContentType: item.contentType)
            pasteboard.write(data.map { .image($0, type: type) } ?? .clear)
        case .file:
            // 一个文件一个 pasteboard item；解析不到路径的用原始路径回写。
            let paths = item.allFilePaths
            guard !paths.isEmpty else {
                pasteboard.write(.clear)
                return
            }
            let resolvedURLs = fileAccess.resolvedFileURLs(for: item)
            let urls = paths.enumerated().map { index, path in
                (index < resolvedURLs.count ? resolvedURLs[index] : nil) ?? URL(fileURLWithPath: path)
            }
            pasteboard.write(.fileURLs(urls))
        case .link:
            var text = item.text
            if text == nil, let full = writer.fetchFullItem(id: item.id) {
                text = full.text
            }
            // 编辑后可能已不是合法 URL，按纯文本写回。
            if let text, let url = URL(string: text), url.scheme != nil {
                pasteboard.write(.url(text))
            } else {
                pasteboard.write(text.map { .text($0, rtf: nil) } ?? .clear)
            }
        case .color:
            var data = item.colorData
            if data == nil, let full = writer.fetchFullItem(id: item.id) {
                data = full.colorData
            }
            pasteboard.write(data.map { .color(text: plainText(of: item), archive: $0) } ?? .clear)
        }
    }
}
