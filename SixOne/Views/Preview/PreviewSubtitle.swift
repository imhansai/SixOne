//
//  PreviewSubtitle.swift
//  SixOne
//  预览顶栏副标题与组信息的纯格式化。
//

import Foundation

@MainActor
enum PreviewSubtitle {
    static func text(_ stats: TextStats?) -> String? {
        guard let stats else { return nil }
        return String(
            format: Localizer.string("%@ characters · %@ words · %@ lines"),
            groupedCount(stats.characters),
            groupedCount(stats.words),
            groupedCount(stats.lines)
        )
    }

    static func image(_ image: PreviewImage?) -> String? {
        guard let image else { return nil }
        let size = image.tier.displaySize
        let sizeText = "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
        return "\(sizeText) · \(ByteCountFormatting.string(fromByteCount: Int64(image.byteCount)))"
    }

    static func group(count: Int, meta: PreviewGroupMeta?) -> String {
        var parts = [String(format: Localizer.string("%@ items"), String(count))]
        if let meta {
            if meta.totalSize > 0 {
                parts.append(ByteCountFormatting.string(fromByteCount: meta.totalSize))
            }
            if meta.missingCount > 0 {
                parts.append(String(format: Localizer.string("%@ missing"), String(meta.missingCount)))
            }
        }
        return parts.joined(separator: " · ")
    }

    /// 组总览顶栏：条数后附带失联数量。
    static func groupCount(count: Int, meta: PreviewGroupMeta?) -> String {
        let countText = String(format: Localizer.string("%@ items"), String(count))
        guard let meta, meta.missingCount > 0 else { return countText }
        return "\(countText) · \(String(format: Localizer.string("%@ missing"), String(meta.missingCount)))"
    }

    static func groupSize(meta: PreviewGroupMeta?) -> String? {
        guard let meta, meta.totalSize > 0 else { return nil }
        return ByteCountFormatting.string(fromByteCount: meta.totalSize)
    }

    static func file(_ meta: PreviewFileMeta?) -> String? {
        guard let meta else { return nil }
        let dateText = meta.modDate?.formattedAbsolute
        if meta.isDirectory {
            guard let dateText else { return nil }
            return "\(Localizer.string("Folder")) · \(dateText)"
        }
        let sizeText = ByteCountFormatting.string(fromByteCount: meta.size ?? 0)
        guard let dateText else { return sizeText }
        return "\(sizeText) · \(dateText)"
    }

    /// 按运行时语言给数字加千分位；模板用 %@ 而非 %d，才能跟随语言的分隔符。
    static func groupedCount(_ value: Int) -> String {
        value.formatted(.number.locale(RuntimeLanguage.shared.locale))
    }
}
