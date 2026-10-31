//
//  FileGroupPreview.swift
//  SixOne

import AppKit
import SwiftUI

/// 多文件条目预览：组内文件按历史条目样式列出（容器 GroupListTableView）。
struct FileGroupPreview: View {
    let context: PanelContext
    let files: [GroupFileEntry]
    let isListActive: Bool
    let sourceAppBundleIdentifier: String?
    let selectedIndex: Int?
    let thumbnailCache: FileGroupThumbnailCache
    let scrollRequest: GroupScrollRequest?
    let scrollRequestID: Int
    /// 确认弹窗期间停掉用户滚动（程序化滚动不受影响）。
    let isScrollBlocked: Bool
    /// 按住 ⌘ 时的编号范围。
    let quickPasteRange: ClosedRange<Int>?
    /// 发布完整可见行范围。
    let onVisibleRowRangeChanged: ((ClosedRange<Int>) -> Void)?
    let onSelect: (Int?) -> Void
    let onPreview: (Int) -> Void
    let onCommand: (GroupFileCommand, Int) -> Void
    let onShare: (Int, NSView) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            GroupListTableView(
                context: context,
                files: files,
                selectedIndex: selectedIndex,
                isListActive: isListActive,
                sourceAppBundleIdentifier: sourceAppBundleIdentifier,
                thumbnailCache: thumbnailCache,
                scrollRequest: scrollRequest,
                scrollRequestID: scrollRequestID,
                isScrollBlocked: isScrollBlocked,
                quickPasteRange: quickPasteRange,
                onVisibleRowRangeChanged: onVisibleRowRangeChanged,
                locale: locale,
                displayScale: displayScale,
                onSelect: onSelect,
                onPreview: onPreview,
                onCommand: onCommand,
                onShare: onShare
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if files.isEmpty {
                // 空结果只给说明，点击仍落到表格（空白处取消选中）。
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
            Text(Localizer.string("No matches found"))
                .font(.system(size: 12))
        }
        .foregroundStyle(.secondary)
    }
}
