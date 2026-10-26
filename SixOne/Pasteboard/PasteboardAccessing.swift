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

/// 系统剪贴板读写口；抽出以便测试，避免覆写用户剪贴板。
protocol PasteboardAccessing {
    /// 变化计数，轮询据此判断是否有新内容。
    var changeCount: Int { get }
    /// 是否标记「不要记录」；只看类型不读内容，须在取 `snapshot` 前判定。
    var isMarkedDoNotRecord: Bool { get }
    /// 值快照；交出快照而非 `NSPasteboardItem`，因为后者不能离开主线程。
    var snapshot: PasteboardSnapshot { get }
    func write(_ payload: PasteboardPayload)
}

struct SystemPasteboard: PasteboardAccessing {
    var changeCount: Int { NSPasteboard.general.changeCount }

    var isMarkedDoNotRecord: Bool {
        PasteboardSnapshot.isMarkedDoNotRecord(NSPasteboard.general.pasteboardItems ?? [])
    }

    var snapshot: PasteboardSnapshot {
        PasteboardSnapshot.capture(from: NSPasteboard.general.pasteboardItems ?? [])
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
