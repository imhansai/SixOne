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

    /// 文件取大小；文件夹与访达空格预览一致，取递归总大小 · 项目数，统计完成前回落到类别名。
    static func fileStats(_ meta: PreviewFileMeta?, folderStats: FolderStats?) -> String? {
        guard let meta else { return nil }
        guard meta.isDirectory else {
            return ByteCountFormatting.string(fromByteCount: meta.size ?? 0)
        }
        guard let folderStats else { return Localizer.string("Folder") }
        let sizeText = ByteCountFormatting.string(fromByteCount: folderStats.totalSize)
        let countTemplate: String.LocalizationValue = folderStats.itemCount == 1 ? "%@ item" : "%@ items"
        let countText = String(
            format: Localizer.string(countTemplate),
            groupedCount(folderStats.itemCount)
        )
        return "\(sizeText) · \(countText)"
    }

    /// 预览底部的时间行：最近修改（可选）、首次记录、最近复制。
    static func timeSegments(
        lastModified: Date?,
        firstCapturedAt: Date,
        lastActivityAt: Date
    ) -> [String] {
        var parts: [String] = []
        if let lastModified { parts.append(lastModifiedLabel(lastModified)) }
        parts.append(firstRecordedTimeLabel(firstCapturedAt))
        parts.append(lastCopiedTimeLabel(lastActivityAt))
        return parts
    }

    static func lastModifiedLabel(_ date: Date) -> String {
        String(format: Localizer.string("Last modified: %@"), date.formattedTimestamp)
    }

    static func firstRecordedTimeLabel(_ date: Date) -> String {
        String(format: Localizer.string("First recorded time: %@"), date.formattedTimestamp)
    }

    static func lastCopiedTimeLabel(_ date: Date) -> String {
        String(format: Localizer.string("Last copied time: %@"), date.formattedTimestamp)
    }

    /// 按运行时语言给数字加千分位；模板用 %@ 而非 %d，才能跟随语言的分隔符。
    static func groupedCount(_ value: Int) -> String {
        value.formatted(.number.locale(RuntimeLanguage.shared.locale))
    }
}
