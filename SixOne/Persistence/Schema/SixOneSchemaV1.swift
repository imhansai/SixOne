//
//  SixOneSchemaV1.swift
//  SixOne
//
//  当前模型定义（唯一一版）；开发阶段不保留历史版本与迁移路径。
//

import Foundation
import SwiftData
import CryptoKit

nonisolated enum SixOneSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] { [ClipboardItem.self] }

    /// `nonisolated` 让后台读路径直接读；少数成员标 `@MainActor`，因创建依赖有序 UUID 与 `Localizer`。
    @Model
    nonisolated final class ClipboardItem {
        /// 两个独立单列索引：`recencyID` 供倒序取窗，`lastActivityAt` 供保留期裁剪。
        /// 索引只在新建库时落盘，既有库需删库重建才生效。
        #Index<ClipboardItem>([\.recencyID], [\.lastActivityAt])

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

        private static let timestampNameFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            return formatter
        }()

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
            switch kind {
            case .text:
                return "t:" + sha256Hex(text ?? "")
            case .file:
                // 排序后哈希：文件顺序无关，也避免长路径串驻留内存。
                return "f:" + sha256Hex(filePaths.sorted().joined(separator: "\n"))
            case .image:
                guard let data = imageData else { return "i:" }
                let head = Data(data.prefix(64)).base64EncodedString()
                let tail = Data(data.suffix(64)).base64EncodedString()
                return "i:\(data.count):\(head):\(tail)"
            case .link:
                return "l:" + sha256Hex(text ?? "")
            case .color:
                return "c:" + sha256Hex(colorData ?? Data())
            }
        }

        private static func sha256Hex(_ value: String) -> String {
            sha256Hex(Data(value.utf8))
        }

        private static func sha256Hex(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
            let normalized = Self.normalizedSearchText(text)
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
            return key
        }

        @discardableResult
        func refreshFilePathsSearchText() -> String? {
            let paths = allFilePaths
            filePathsSearchText = paths.isEmpty ? nil : paths.joined(separator: " ")
            return filePathsSearchText
        }

        /// 单行化搜索文本：空格原样保留，全空白视为 nil。
        static func normalizedSearchText(_ raw: String?) -> String? {
            guard let raw else { return nil }
            // 在 Scalar 层替换：CRLF 会被合成单个 Character，按 Character 处理会漏转。
            let mappedScalars = raw.unicodeScalars.map { scalar -> Unicode.Scalar in
                Self.searchLineSeparators.contains(scalar)
                    ? Unicode.Scalar(0x20)!
                    : scalar
            }
            let mapped = String(mappedScalars.map(Character.init))
            return mapped.allSatisfy(\.isWhitespace) ? nil : mapped
        }

        private static let searchLineSeparators: Set<Unicode.Scalar> = [
            Unicode.Scalar(0x0A)!, Unicode.Scalar(0x0D)!,
            Unicode.Scalar(0x0B)!, Unicode.Scalar(0x0C)!,
            Unicode.Scalar(0x85)!, Unicode.Scalar(0x2028)!,
            Unicode.Scalar(0x2029)!,
        ]

        // MARK: - 标题生成

        /// 空白折叠为单个空格，超过 `maxLength` 以 "..." 收尾。
        private static func singleLineTruncated(_ text: String, maxLength: Int = 200) -> String {
            let joined = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            return joined.count > maxLength ? String(joined.prefix(maxLength)) + "..." : joined
        }

        @MainActor
        private func computeTitle() -> String {
            switch kind {
            case .text:
                guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                    return Localizer.string("Text")
                }
                return Self.singleLineTruncated(trimmed)
            case .image:
                if let filePath, !filePath.isEmpty {
                    let fileName = URL(fileURLWithPath: filePath).lastPathComponent
                    if !fileName.isEmpty {
                        return fileName
                    }
                }
                let extensionName = (contentType ?? "").lowercased()
                let suffix = PasteboardFormat.imageFileExtensions.contains(extensionName) ? extensionName : "png"
                return Self.timestampNameFormatter.string(from: lastActivityAt) + "." + suffix
            case .file:
                let paths = allFilePaths
                let name = URL(fileURLWithPath: paths.first ?? "").lastPathComponent
                guard !name.isEmpty else { return Localizer.string("File") }
                guard paths.count > 1 else { return name }
                return Localizer.groupTitle(firstName: name, count: paths.count)
            case .link:
                guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                    return Localizer.string("Link")
                }
                return Self.singleLineTruncated(trimmed)
            case .color:
                return colorHexString ?? Localizer.string("Color")
            }
        }
    }
}

typealias ClipboardItem = SixOneSchemaV1.ClipboardItem
