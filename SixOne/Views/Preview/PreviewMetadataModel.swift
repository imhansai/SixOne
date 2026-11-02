//
//  PreviewMetadataModel.swift
//  SixOne
//  预览的异步元数据：图片解码、文件/组 stat 与文本统计。
//

import Foundation
import Observation

nonisolated struct PreviewImage: Sendable {
    let tier: PreviewImageDecoder.Tier
    let byteCount: Int
}

nonisolated struct PreviewFileMeta: Sendable {
    let size: Int64?
    let modDate: Date?
    let isDirectory: Bool
}

nonisolated struct PreviewGroupMeta: Sendable {
    let totalSize: Int64
    let missingCount: Int
}

/// 预览详情的数据补齐：大字段与文件 stat 都不在列表快照里，这里按需读取。
@Observable
@MainActor
final class PreviewMetadataModel {
    let item: ClipboardItem
    private let previewState: PreviewState
    private let manager: ClipboardManager
    private let textStatsCache: ClipboardTextStatsCache

    private(set) var image: PreviewImage?
    private(set) var imageData: Data?
    private(set) var imageLoadFailed = false
    private(set) var fileMeta: PreviewFileMeta?
    private(set) var groupMeta: PreviewGroupMeta?
    private(set) var textStats: TextStats?
    /// 编辑保存后自增，驱动文本统计重新读取。
    private(set) var statsRevision = 0

    init(
        item: ClipboardItem,
        previewState: PreviewState,
        manager: ClipboardManager,
        textStatsCache: ClipboardTextStatsCache
    ) {
        self.item = item
        self.previewState = previewState
        self.manager = manager
        self.textStatsCache = textStatsCache
    }

    var textStatsTaskID: String {
        "\(item.id.uuidString)-\(statsRevision)"
    }

    /// 图片条目按 id 补齐 imageData 并解码（列表查询不含大字段）。
    func loadImageIfNeeded() async {
        guard item.kind == .image, image == nil else { return }
        let data: Data?
        if let imageData = item.imageData {
            data = imageData
        } else {
            data = await manager.loadImageData(id: item.id)
        }
        guard let data else {
            imageLoadFailed = true
            return
        }
        let tier = await PreviewImageDecoder.decode(data, maxPixelSize: ClipboardLayout.previewImageBasePixelSize)
        // 可能已切走/关闭预览，迟到结果丢弃。
        guard !Task.isCancelled, image == nil else { return }
        guard let tier else {
            imageLoadFailed = true
            return
        }
        imageData = data
        image = PreviewImage(tier: tier, byteCount: data.count)
    }

    func finerImage(maxPixelSize: Int) async -> PreviewImageDecoder.Tier? {
        guard let imageData else { return nil }
        return await PreviewImageDecoder.decode(imageData, maxPixelSize: maxPixelSize)
    }

    func loadTextStats() async {
        guard item.kind == .text || item.kind == .link, let text = item.text else { return }
        // 超大正文统计需全量扫描，副标题改显示截断提示。
        guard !item.exceedsTextPreviewLimit else { return }
        textStats = await textStatsCache.stats(for: item.id, text: text)
    }

    func invalidateTextStats() {
        textStatsCache.invalidate(for: item.id)
        statsRevision += 1
    }

    /// 读取并缓存文件元数据；组元数据后台计算，避免上百文件 stat 卡主线程。
    func refreshFileMetadata(fileURL: URL?, groupURLs: [URL?]) {
        guard item.kind == .file else { return }
        if item.fileCount > 1 {
            if groupMeta == nil {
                let itemID = item.id
                Task { [weak self] in
                    let meta = await Self.groupMeta(for: groupURLs)
                    guard let self, self.previewState.item?.id == itemID else { return }
                    self.groupMeta = meta
                }
            }
            refreshGroupFileMeta(groupURLs: groupURLs)
            return
        }
        guard let fileURL, fileMeta == nil else { return }
        fileMeta = Self.fileMeta(at: fileURL)
    }

    private func refreshGroupFileMeta(groupURLs: [URL?]) {
        guard let index = previewState.groupFileIndex,
              groupURLs.indices.contains(index),
              let url = groupURLs[index] else {
            fileMeta = nil
            return
        }
        fileMeta = Self.fileMeta(at: url)
    }

    private static func fileMeta(at url: URL) -> PreviewFileMeta {
        let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        )
        return PreviewFileMeta(
            size: values?.fileSize.map(Int64.init),
            modDate: values?.contentModificationDate,
            isDirectory: values?.isDirectory ?? false
        )
    }

    /// 组元数据：按解析后 URL 统计非目录文件大小，避免移动后少算。
    private nonisolated static func groupMeta(for urls: [URL?]) async -> PreviewGroupMeta {
        var totalSize: Int64 = 0
        var missingCount = 0
        for url in urls {
            guard let url else {
                missingCount += 1
                continue
            }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            guard let size = values?.fileSize, values?.isDirectory != true else { continue }
            totalSize += Int64(size)
        }
        return PreviewGroupMeta(totalSize: totalSize, missingCount: missingCount)
    }
}
