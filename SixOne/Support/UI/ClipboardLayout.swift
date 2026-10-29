//
//  ClipboardLayout.swift
//  SixOne
//  面板布局共享常量，避免魔法数字漂移。

import AppKit
import CoreGraphics

enum ClipboardLayout {
    /// 面板窗口尺寸；窗口、内容视图与列表共用。
    static let panelWidth: CGFloat = 640
    static let panelHeight: CGFloat = 545
    static var panelSize: NSSize { NSSize(width: panelWidth, height: panelHeight) }

    static let rowHeight: CGFloat = 58
    /// 列表上下留白：并进首末行高度，并随滚动进入视野。
    /// 不用 `contentInsets`：它会把可滚动范围撑到内容之外。
    static let verticalPadding: CGFloat = 8
    /// 顶栏高度，含拖拽区；列表与预览共用。
    static let headerHeight: CGFloat = 54
    /// 顶栏内容的左右安全边距。
    static let headerHorizontalInset: CGFloat = 10
    /// 顶栏操作按钮之间的间距；预览与文件组顶栏共用。
    static let headerActionSpacing: CGFloat = 12
    static let contentInset: CGFloat = 18
    /// 路径条高度与上下留白。
    static let pathBarHeight: CGFloat = 20
    static let pathBarInset: CGFloat = 13

    /// 预览内容区尺寸（未扣路径条）。
    static var previewContentWidth: CGFloat { panelWidth - contentInset * 2 }
    static var previewContentHeight: CGFloat { panelHeight - headerHeight - contentInset * 2 }

    /// 基准解码图的长边上限：内容区最长边的 4 倍，覆盖 1×–2× 缩放。
    static var previewImageBasePixelSize: Int {
        Int((max(previewContentWidth, previewContentHeight) * 4).rounded(.up))
    }

    static let previewTitleInset: CGFloat = 10
    /// 视口大致可容纳的行数，用于判断是否滚到深处。
    static let viewportRowCount = 8
    /// 行的水平基准内缩。
    static let rowHorizontalInset: CGFloat = 8
    /// 浮层滚动条滑块在最外侧占用的宽度。
    static let overlayScrollerKnobClearance: CGFloat = 14

    static let geometryTolerance: CGFloat = 0.5

    /// 选中高亮的尾部内缩：浮层滚动条不占布局宽度，尾部要多让一段。
    static func rowSelectionTrailingInset(usesOverlayScrollers: Bool) -> CGFloat {
        guard usesOverlayScrollers else { return rowHorizontalInset }
        return max(rowHorizontalInset, overlayScrollerKnobClearance + 2)
    }

    /// 行尾复制按钮的边长与内缩；SwiftUI 布局与命中目标共用。
    static let rowCopyButtonSize: CGFloat = 26
    static func rowCopyButtonTrailingInset(usesOverlayScrollers: Bool) -> CGFloat {
        rowSelectionTrailingInset(usesOverlayScrollers: usesOverlayScrollers) + rowHorizontalInset
    }

    /// 行尾操作列的宽度：复制按钮 + 到行尾的内缩。
    static func rowCopyButtonColumnWidth(usesOverlayScrollers: Bool) -> CGFloat {
        rowCopyButtonTrailingInset(usesOverlayScrollers: usesOverlayScrollers) + rowCopyButtonSize
    }

    /// 复制按钮在操作列里的矩形（原点左上，与 SwiftUI 同向）。
    static func rowCopyButtonRect(listTopPadding: CGFloat) -> CGRect {
        CGRect(
            x: 0,
            y: listTopPadding + (rowHeight - rowCopyButtonSize) / 2,
            width: rowCopyButtonSize,
            height: rowCopyButtonSize
        )
    }

    // MARK: - 文件组预览列表

    static let groupRowThumbnailSize: CGFloat = 40
    /// 列表上下留白，与历史列表一致。
    static let groupListPadding: CGFloat = verticalPadding
}
