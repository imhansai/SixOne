//
//  ClipboardItemDerivation.swift
//  SixOne
//
//  条目派生值的纯工具：去重 key、搜索快照与标题生成，模型只负责存取字段。
//

import CryptoKit
import Foundation

nonisolated enum ContentFingerprint {
    static func key(
        kind: ClipboardItemKind,
        text: String?,
        imageData: Data?,
        filePaths: [String],
        colorData: Data?
    ) -> String {
        switch kind {
        case .text:
            return "t:" + sha256Hex(text ?? "")
        case .file:
            // 排序后哈希：文件顺序无关，也避免长路径串驻留内存。
            return "f:" + sha256Hex(filePaths.sorted().joined(separator: "\n"))
        case .image:
            guard let data = imageData else { return "i:" }
            // 必须覆盖整段数据：同尺寸、同首尾的图片不能碰撞。
            return "i:" + sha256Hex(data)
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
}

nonisolated enum SearchSnapshotter {
    /// 单行化搜索文本：空格原样保留，全空白视为 nil。
    static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        // 在 Scalar 层替换：CRLF 会被合成单个 Character，按 Character 处理会漏转。
        let mappedScalars = raw.unicodeScalars.map { scalar -> Unicode.Scalar in
            lineSeparators.contains(scalar) ? Unicode.Scalar(0x20)! : scalar
        }
        let mapped = String(mappedScalars.map(Character.init))
        return mapped.allSatisfy(\.isWhitespace) ? nil : mapped
    }

    static func filePaths(_ paths: [String]) -> String? {
        paths.isEmpty ? nil : paths.joined(separator: " ")
    }

    private static let lineSeparators: Set<Unicode.Scalar> = [
        Unicode.Scalar(0x0A)!, Unicode.Scalar(0x0D)!,
        Unicode.Scalar(0x0B)!, Unicode.Scalar(0x0C)!,
        Unicode.Scalar(0x85)!, Unicode.Scalar(0x2028)!,
        Unicode.Scalar(0x2029)!,
    ]
}

nonisolated enum AliasNormalizer {
    /// 别名长度上限；弹窗与归一化共用。
    static let maxLength = 100

    /// 空白折叠为单个空格、去掉首尾，超长截断；只有不可见字符视为未设置。
    static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.unicodeScalars.contains(where: isVisible) else { return nil }
        return String(collapsed.prefix(maxLength))
    }

    /// 空串按未设置处理，兼容非归一化写入。
    static func displayable(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    private static func isVisible(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        guard !properties.isWhitespace, !blankScalars.contains(scalar) else { return false }
        switch properties.generalCategory {
        case .format, .control, .nonspacingMark, .spacingMark, .enclosingMark:
            return false
        default:
            return true
        }
    }

    /// 常见“占位但不可见”的字符。
    private static let blankScalars: Set<Unicode.Scalar> = [
        Unicode.Scalar(0x2800)!, Unicode.Scalar(0x3164)!, Unicode.Scalar(0xFFA0)!,
        Unicode.Scalar(0x115F)!, Unicode.Scalar(0x1160)!,
        Unicode.Scalar(0x17B4)!, Unicode.Scalar(0x17B5)!,
    ]
}

nonisolated enum ItemTitleFormatter {
    @MainActor
    static func title(
        kind: ClipboardItemKind,
        text: String?,
        filePath: String?,
        filePaths: [String],
        contentType: String?,
        colorHex: String?,
        lastActivityAt: Date
    ) -> String {
        switch kind {
        case .text:
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return Localizer.string("Text")
            }
            return singleLineTruncated(trimmed)
        case .image:
            if let filePath, !filePath.isEmpty {
                let fileName = URL(fileURLWithPath: filePath).lastPathComponent
                if !fileName.isEmpty {
                    return fileName
                }
            }
            let extensionName = (contentType ?? "").lowercased()
            let suffix = PasteboardFormat.imageFileExtensions.contains(extensionName) ? extensionName : "png"
            return timestampNameFormatter.string(from: lastActivityAt) + "." + suffix
        case .file:
            let name = URL(fileURLWithPath: filePaths.first ?? "").lastPathComponent
            guard !name.isEmpty else { return Localizer.string("File") }
            guard filePaths.count > 1 else { return name }
            return Localizer.groupTitle(firstName: name, count: filePaths.count)
        case .link:
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return Localizer.string("Link")
            }
            return singleLineTruncated(trimmed)
        case .color:
            return colorHex ?? Localizer.string("Color")
        }
    }

    /// 空白折叠为单个空格，超过 `maxLength` 以 "..." 收尾。
    private static func singleLineTruncated(_ text: String, maxLength: Int = 200) -> String {
        let joined = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return joined.count > maxLength ? String(joined.prefix(maxLength)) + "..." : joined
    }

    private static let timestampNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
