//
//  FakePasteboard.swift
//  SixOneTests
//

import AppKit
@testable import SixOne

/// 内存剪贴板：写入推进 changeCount，内容可读回，内部走与生产相同的快照装配路径。
@MainActor
final class FakePasteboard: PasteboardAccessing {
    private(set) var changeCount = 0
    private(set) var items: [NSPasteboardItem] = []
    /// 最近一次写回的内容。
    private(set) var lastWrite: PasteboardPayload?

    var isMarkedDoNotRecord: Bool {
        PasteboardSnapshot.isMarkedDoNotRecord(items)
    }

    var snapshot: PasteboardSnapshot {
        PasteboardSnapshot.capture(from: items)
    }

    /// 模拟带「不要记录」标记的复制。
    func simulateConcealedCopy(text: String) {
        let item = Self.item(text, type: .string)
        item.setString("1", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        simulateCopy([item])
    }

    /// 模拟一次外部复制。
    func simulateCopy(_ items: [NSPasteboardItem]) {
        self.items = items
        changeCount += 1
    }

    /// 模拟一次纯文本复制。
    func simulateCopy(text: String) {
        simulateCopy([Self.item(text, type: .string)])
    }

    /// 模拟多文件复制（一个文件一个 item）。
    func simulateCopy(fileURLs: [URL]) {
        simulateCopy(fileURLs.map { Self.item($0.absoluteString, type: .fileURL) })
    }

    func write(_ payload: PasteboardPayload) {
        lastWrite = payload
        items = switch payload {
        case .clear:
            []
        case let .text(text, _):
            [Self.item(text, type: .string)]
        case let .image(data, type):
            [Self.item(data, type: type)]
        case let .fileURLs(urls):
            urls.map { Self.item($0.absoluteString, type: .fileURL) }
        case let .url(urlString):
            [Self.urlItem(urlString)]
        case let .color(text, archive):
            [Self.colorItem(text: text, archive: archive)]
        }
        changeCount += 1
    }

    private static func item(_ value: String, type: NSPasteboard.PasteboardType) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(value, forType: type)
        return item
    }

    /// 链接类型与纯文本写在同一 item 上。
    private static func urlItem(_ value: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(value, forType: .URL)
        item.setString(value, forType: .string)
        return item
    }

    /// 颜色按标准属性列表写入（顶层 NSData），文本写在同一 item 上。
    private static func colorItem(text: String?, archive: Data) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setPropertyList(archive, forType: .color)
        if let text {
            item.setString(text, forType: .string)
        }
        return item
    }

    private static func item(_ data: Data, type: NSPasteboard.PasteboardType) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(data, forType: type)
        return item
    }
}
