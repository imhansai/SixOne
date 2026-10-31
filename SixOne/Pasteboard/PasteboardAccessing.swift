//
//  PasteboardAccessing.swift
//  SixOne
//

import AppKit

/// 要写回剪贴板的内容。
enum PasteboardPayload: Equatable {
    case clear
    case text(String, rtf: Data?)
    case image(Data, type: NSPasteboard.PasteboardType)
    /// 文件 URL；多个时写成多个 item 以便访达落地。
    case fileURLs([URL])
    /// 链接：同写 URL 与纯文本，两类应用都能贴。
    case url(String)
    /// 颜色：NSColor 归档 + 十六进制文本。
    case color(text: String?, archive: Data)
}

/// 一次读取的结果：判定与快照必须基于同一份 pasteboardItems。
enum PasteboardReadResult {
    /// 可记录；changeCount 是读到这份快照时的那一次。
    case captured(PasteboardSnapshot, changeCount: Int)
    /// 被标记为「不要记录」；只看类型，未读内容。
    case markedDoNotRecord(changeCount: Int)
    /// 剪贴板为空，没有可记录的内容。
    case empty(changeCount: Int)
    /// 读取期间剪贴板又被改写：这份快照可能是半截的，本轮作废。
    case unstable
}

/// 系统剪贴板读写口；抽出以便测试，避免覆写用户剪贴板。
protocol PasteboardAccessing {
    /// 变化计数，轮询据此判断是否有新内容。
    var changeCount: Int { get }
    /// 一次读取：先判「不要记录」，再由同一份 items 生成快照。
    /// 「不要记录」的判定必须先于读内容，且不能与快照各读一次剪贴板。
    func readRecordableSnapshot() -> PasteboardReadResult
    func write(_ payload: PasteboardPayload)
}

struct SystemPasteboard: PasteboardAccessing {
    var changeCount: Int { NSPasteboard.general.changeCount }

    func readRecordableSnapshot() -> PasteboardReadResult {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        // 只读一次剪贴板：判定与快照共用这份 items，避免两次读取之间的 TOCTOU。
        let items = pasteboard.pasteboardItems ?? []
        guard !PasteboardSnapshot.isMarkedDoNotRecord(items) else {
            return .markedDoNotRecord(changeCount: changeCount)
        }
        guard !items.isEmpty else { return .empty(changeCount: changeCount) }
        let snapshot = PasteboardSnapshot.capture(from: items)
        // 读取期间被改写：快照可能只拷到一半，丢弃等下一轮。
        guard pasteboard.changeCount == changeCount else { return .unstable }
        return .captured(snapshot, changeCount: changeCount)
    }

    func write(_ payload: PasteboardPayload) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch payload {
        case .clear:
            break
        case let .text(text, rtf):
            if let rtf {
                pasteboard.setData(rtf, forType: .rtf)
            }
            pasteboard.setString(text, forType: .string)
        case let .image(data, type):
            pasteboard.setData(data, forType: type)
        case let .fileURLs(urls):
            guard let first = urls.first else { return }
            guard urls.count > 1 else {
                pasteboard.setString(first.absoluteString, forType: .fileURL)
                return
            }
            pasteboard.writeObjects(urls.map { url in
                let item = NSPasteboardItem()
                item.setString(url.absoluteString, forType: .fileURL)
                return item
            })
        case let .url(urlString):
            pasteboard.setString(urlString, forType: .URL)
            pasteboard.setString(urlString, forType: .string)
        case let .color(text, archive):
            // 必须 setPropertyList：标准形态是顶层 NSData 的属性列表，直接 setData 会让标准读法崩溃。
            pasteboard.setPropertyList(archive, forType: .color)
            if let text {
                pasteboard.setString(text, forType: .string)
            }
        }
    }
}
