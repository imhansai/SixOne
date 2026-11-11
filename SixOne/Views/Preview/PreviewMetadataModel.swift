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

/// 文件夹内容的递归统计，对应访达空格预览的「大小 · 项目数」。
nonisolated struct FolderStats: Sendable, Equatable {
    let totalSize: Int64
    let itemCount: Int
}

nonisolated struct PreviewGroupMeta: Sendable {
    let totalSize: Int64
    let missingCount: Int
    /// 组内文件的最新修改时间。
    let latestModDate: Date?

    init(totalSize: Int64, missingCount: Int, latestModDate: Date? = nil) {
        self.totalSize = totalSize
        self.missingCount = missingCount
        self.latestModDate = latestModDate
    }
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
    private(set) var folderStats: FolderStats?
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

    /// 读取并缓存文件元数据；目录统计与组元数据后台计算，避免卡主线程。
    func refreshFileMetadata(fileURL: URL?, groupURLs: [URL?]) async {
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
            await refreshGroupFileMeta(groupURLs: groupURLs)
            return
        }
        guard let fileURL else { return }
        if fileMeta == nil {
            fileMeta = Self.fileMeta(at: fileURL)
        }
        await loadFolderStatsIfNeeded(url: fileURL)
    }

    private func refreshGroupFileMeta(groupURLs: [URL?]) async {
        folderStats = nil
        guard let index = previewState.groupFileIndex,
              groupURLs.indices.contains(index),
              let url = groupURLs[index] else {
            fileMeta = nil
            return
        }
        fileMeta = Self.fileMeta(at: url)
        await loadFolderStatsIfNeeded(url: url)
    }

    private func loadFolderStatsIfNeeded(url: URL) async {
        guard folderStats == nil, fileMeta?.isDirectory == true else { return }
        let itemID = item.id
        let stats = await Self.computeFolderStats(at: url)
        guard !Task.isCancelled, let stats, previewState.item?.id == itemID else { return }
        folderStats = stats
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

    /// 递归枚举目录，累加普通文件大小并统计项目数；在后台线程执行，关闭预览时随之取消。
    nonisolated static func computeFolderStats(at url: URL) async -> FolderStats? {
        let scan = Task.detached(priority: .utility) {
            scanFolder(at: url)
        }
        return await withTaskCancellationHandler {
            await scan.value
        } onCancel: {
            scan.cancel()
        }
    }

    private nonisolated static func scanFolder(at url: URL) -> FolderStats? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        // 无权限的子目录跳过，其余继续统计。
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return nil }
        var totalSize: Int64 = 0
        var itemCount = 0
        for case let child as URL in enumerator {
            // 预览关闭或切换条目时任务被取消，大目录不必扫完。
            guard !Task.isCancelled else { return nil }
            itemCount += 1
            guard let values = try? child.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            totalSize += Int64(values.fileSize ?? 0)
        }
        return FolderStats(totalSize: totalSize, itemCount: itemCount)
    }

    /// 组元数据：按解析后 URL 统计非目录文件大小，避免移动后少算。
    private nonisolated static func groupMeta(for urls: [URL?]) async -> PreviewGroupMeta {
        var totalSize: Int64 = 0
        var missingCount = 0
        var latestModDate: Date?
        for url in urls {
            guard let url else {
                missingCount += 1
                continue
            }
            let values = try? url.resourceValues(
                forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey]
            )
            if let modDate = values?.contentModificationDate {
                latestModDate = max(latestModDate ?? modDate, modDate)
            }
            guard let size = values?.fileSize, values?.isDirectory != true else { continue }
            totalSize += Int64(size)
        }
        return PreviewGroupMeta(
            totalSize: totalSize,
            missingCount: missingCount,
            latestModDate: latestModDate
        )
    }
}
