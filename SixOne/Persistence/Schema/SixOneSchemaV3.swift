//
//  SixOneSchemaV3.swift
//  SixOne
//
//  当前模型定义（V3）。V3 在 V2 上给 `id` 加索引，并记录缩略图生成版本；
//  V2 → V3 只做轻量结构迁移，旧缩略图由列表惰性重算。V1/V2 已冻结，改字段从 V3 复制出新版本。
//

import Foundation
import SwiftData

nonisolated enum SixOneSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] { [ClipboardItem.self] }

    /// `nonisolated` 让后台读路径直接读；少数成员标 `@MainActor`，因创建依赖有序 UUID 与 `Localizer`。
    @Model
    nonisolated final class ClipboardItem {
        /// 四个独立单列索引：`id` 供按 id 取数，`recencyID` 供倒序取窗，
        /// `lastActivityAt` 供保留期裁剪，`contentKeySnapshot` 供去重等值查询。
        /// 新增索引必须随版本迁移落地，否则既有库不会补上。
        #Index<ClipboardItem>([\.id], [\.recencyID], [\.lastActivityAt], [\.contentKeySnapshot])

        /// 稳定身份（UUIDv7）。
        var id: UUID
        /// 排序键（UUIDv7）：创建时等于 id，触达时刷新。
        var recencyID: UUID
        var kindRaw: String
        var text: String?
        /// RTF 富文本；外部存储避免拖慢主表与 WAL。
        @Attribute(.externalStorage) var attributedTextData: Data?
        /// 单行化搜索快照：换行类字符换成空格，其余空白保留。
        var searchText: String?
        /// 位图原样数据；外部存储避免拖慢 WAL。
        @Attribute(.externalStorage) var imageData: Data?
        /// 列表缩略图，避免常驻原图。
        var thumbnailData: Data?
        /// 缩略图生成版本；nil/旧版本会在列表显示时按当前尺寸重算。
        var thumbnailVersion: Int?
        /// 单路径列；多文件条目恒等于 `filePaths.first`。
        var filePath: String?
        var filePaths: [String]?
        /// 文件条目的安全作用域 bookmark。
        var securityScopeBookmark: Data?
        var securityScopeBookmarks: Data?
        /// 路径搜索快照：多文件路径以空格连接。
        var filePathsSearchText: String?
        var contentType: String?
        /// 颜色条目的 NSColor 归档本体，归一形态以便跨来源去重。
        var colorData: Data?
        var sourceAppBundleIdentifier: String?
        var sourceAppName: String?
        /// 首次捕获时间，之后不变。
        var firstCapturedAt: Date
        /// 最近触达时间；列表副标题与保留期裁剪使用。
        var lastActivityAt: Date
        /// 列表标题快照；nil 时现算，避免列表常驻超大正文。
        var titleSnapshot: String?
        /// 去重 key 快照；外部重复拷贝可等值查询，为空不参与去重。
        var contentKeySnapshot: String?
        /// 去重 key 的算法版本；nil 表示 V1 旧数据，迁移时统一补算。
        var contentKeyVersion: Int?

        // MARK: - 初始化

        @MainActor
        init(
            kind: ClipboardItemKind,
            text: String? = nil,
            attributedTextData: Data? = nil,
            imageData: Data? = nil,
            thumbnailData: Data? = nil,
            filePath: String? = nil,
            filePaths: [String]? = nil,
            contentType: String? = nil,
            colorData: Data? = nil,
            sourceAppBundleIdentifier: String? = nil,
            sourceAppName: String? = nil
        ) {
            let newID = OrderedUUID.make()
            self.id = newID
            self.recencyID = newID
            self.kindRaw = kind.rawValue
            self.text = text
            self.attributedTextData = attributedTextData
            self.searchText = nil
            self.imageData = imageData
            self.thumbnailData = thumbnailData
            // 收敛成 filePath 恒为首个文件。
            self.filePath = filePath ?? filePaths?.first
            self.filePaths = filePaths
            self.contentType = contentType
            self.colorData = colorData
            self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
            self.sourceAppName = sourceAppName
            let capturedAt = Date()
            self.firstCapturedAt = capturedAt
            self.lastActivityAt = capturedAt
            if kind == .text || kind == .link {
                refreshSearchText()
            } else if kind == .color {
                refreshColorSearchText()
            }
            refreshFilePathsSearchText()
        }

        // MARK: - 派生属性

        var kind: ClipboardItemKind {
            get { ClipboardItemKind(rawValue: kindRaw) ?? .text }
            set { kindRaw = newValue.rawValue }
        }

        /// 全部文件路径：多文件返回全部，单文件/图片一条，非文件为空。
        var allFilePaths: [String] {
            if let filePaths, !filePaths.isEmpty { return filePaths }
            return filePath.map { [$0] } ?? []
        }

        var fileCount: Int { allFilePaths.count }

        var colorHexString: String? {
            guard let colorData else { return nil }
            return PasteboardFormat.hexString(ofColorData: colorData)
        }

        // MARK: - 内容身份与去重

        /// 当前去重算法版本（与 schema 版本独立）；改算法时递增，后台会按版本重算旧条目。
        static let currentContentKeyVersion = 2
        /// 当前缩略图生成版本；改尺寸/编码时递增，旧缩略图可据此识别并重算。
        static let currentThumbnailVersion = 2
        /// V2 时代的缩略图版本（256px）；旧库迁移后保持 nil，列表看到非当前版本会惰性重算。
        static let legacyThumbnailVersion = 1

        /// 去重稳定标识；文本用 SHA256，避免超大文本驻留内存。
        var contentKey: String {
            Self.contentKey(
                kind: kind,
                text: text,
                imageData: imageData,
                filePaths: allFilePaths,
                colorData: colorData
            )
        }

        static func contentKey(
            kind: ClipboardItemKind,
            text: String?,
            imageData: Data?,
            filePaths: [String],
            colorData: Data? = nil
        ) -> String {
            ContentFingerprint.key(
                kind: kind,
                text: text,
                imageData: imageData,
                filePaths: filePaths,
                colorData: colorData
            )
        }

        // MARK: - 标题与搜索快照

        /// 列表标题；文件组按当前语言现算，避免旧快照停留在旧文案。
        @MainActor
        var displayTitle: String {
            if kind == .file, fileCount > 1 { return computeTitle() }
            if let titleSnapshot, !titleSnapshot.isEmpty {
                return titleSnapshot
            }
            return computeTitle()
        }

        @MainActor
        @discardableResult
        func refreshTitleSnapshot() -> String {
            let title = computeTitle()
            titleSnapshot = title
            return title
        }

        @discardableResult
        func refreshSearchText() -> String? {
            let normalized = SearchSnapshotter.normalized(text)
            searchText = normalized
            return normalized
        }

        @discardableResult
        func refreshColorSearchText() -> String? {
            searchText = colorHexString
            return searchText
        }

        /// 生成并写入去重快照，只在内容写入路径调用。
        @discardableResult
        func refreshContentKey() -> String {
            let key = contentKey
            contentKeySnapshot = key
            contentKeyVersion = Self.currentContentKeyVersion
            return key
        }

        @discardableResult
        func refreshFilePathsSearchText() -> String? {
            filePathsSearchText = SearchSnapshotter.filePaths(allFilePaths)
            return filePathsSearchText
        }

        /// 单行化搜索文本：空格原样保留，全空白视为 nil。
        static func normalizedSearchText(_ raw: String?) -> String? {
            SearchSnapshotter.normalized(raw)
        }

        // MARK: - 标题生成

        @MainActor
        private func computeTitle() -> String {
            ItemTitleFormatter.title(
                kind: kind,
                text: text,
                filePath: filePath,
                filePaths: allFilePaths,
                contentType: contentType,
                colorHex: colorHexString,
                lastActivityAt: lastActivityAt
            )
        }
    }
}

/// 当前版本：业务代码只认这个名字；升级 schema 时改这里，不要改已冻结的旧版本。
typealias ClipboardItem = SixOneSchemaV3.ClipboardItem
