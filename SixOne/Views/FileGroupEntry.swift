//
//  FileGroupEntry.swift
//  SixOne
//  文件组条目的动作、行数据与滚动几何。
//

import AppKit

/// 文件组某一项的右键动作；分享单独走 onShare，因为需要行视图当锚点。
enum GroupFileCommand {
    case open
    case reveal
    case paste
    case copy
}

/// 组内一行：路径 + bookmark 解析出的 URL（nil 表示失联）；下标与 allFilePaths 对齐。
struct GroupFileEntry: Identifiable, Equatable, Hashable {
    let index: Int
    /// 捕获时的路径，可能已不存在。
    let path: String
    let url: URL?
    /// 行身份：组内原始下标，筛选/重排后不变。
    let rowID: UUID

    var id: Int { index }

    init(index: Int, path: String, url: URL?) {
        self.index = index
        self.path = path
        self.url = url
        self.rowID = Self.makeRowID(index: index)
    }

    /// 显示名：优先解析后的当前路径，避免重命名后与缩略图不符。
    var name: String {
        URL(fileURLWithPath: url?.path ?? path).lastPathComponent
    }

    /// 下标唯一且稳定，无需对路径做摘要。
    private static func makeRowID(index: Int) -> UUID {
        let value = UInt64(bitPattern: Int64(index))
        return UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            UInt8(truncatingIfNeeded: value >> 56),
            UInt8(truncatingIfNeeded: value >> 48),
            UInt8(truncatingIfNeeded: value >> 40),
            UInt8(truncatingIfNeeded: value >> 32),
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value)
        ))
    }
}

/// 组内列表滚动几何：把行连同上下留白滚进视口，两端由文档边界钳住。
enum FileGroupListScrollGeometry {
    static func targetOriginY(
        rowRect: CGRect,
        visible: CGRect,
        documentHeight: CGFloat
    ) -> CGFloat {
        HistoryListScrollGeometry.targetOriginY(
            paddedRow: rowRect.insetBy(dx: 0, dy: -ClipboardLayout.groupListPadding),
            visible: visible,
            documentHeight: documentHeight
        )
    }
}
