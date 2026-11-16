//
//  FileGroupContent.swift
//  SixOne
//
//  文件组：列表总览与组内单文件预览；列表用透明度隐藏以保住滚动位置。
//

import AppKit
import SwiftUI

struct FileGroupContent: View {
    let item: ClipboardItem
    /// 与 allFilePaths 一一对应；nil 表示文件已失联。
    let groupURLs: [URL?]

    @Environment(PanelContext.self) private var context

    private var previewState: PreviewState { context.previewState }

    var body: some View {
        let coordinator = GroupPreviewCoordinator(
            item: item,
            groupURLs: groupURLs,
            previewState: previewState,
            groupActions: context.groupActions,
            shellActions: context.shellActions
        )
        let viewingIndex = coordinator.viewingIndex
        return ZStack {
            GroupFileListView(
                context: context,
                files: coordinator.visibleEntries,
                isListActive: !previewState.isGroupFilterFocused,
                sourceAppBundleIdentifier: item.sourceAppBundleIdentifier,
                selectedIndex: previewState.groupSelectedIndex,
                thumbnailCache: context.caches.fileGroupThumbnails,
                scrollRequest: previewState.groupScrollRequest,
                scrollRequestID: previewState.groupScrollRequestID,
                isScrollBlocked: context.confirmationState.isPresenting,
                quickPasteRange: quickPasteRange,
                onVisibleRowRangeChanged: coordinator.visibleRangeDidChange,
                onSelect: coordinator.select,
                onPreview: coordinator.preview,
                onCommand: coordinator.handle,
                onShare: coordinator.share
            )
            .opacity(viewingIndex == nil ? 1 : 0)
            .allowsHitTesting(viewingIndex == nil)
            .accessibilityHidden(viewingIndex != nil)

            if let index = viewingIndex {
                // 单文件查看态复用文件预览的内容槽；顶栏由 PreviewDetailView 统一给出。
                Group {
                    if let url = groupURLs[index] {
                        FilePreviewContent(url: url)
                    } else {
                        missingGroupFileNotice(name: coordinator.entries[index].name)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// 按住 ⌘ 时才参与编号。
    private var quickPasteRange: ClosedRange<Int>? {
        guard context.quickPasteHintState.isShowing else { return nil }
        return previewState.groupVisibleRowRange
    }

    private func missingGroupFileNotice(name: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(String(
                format: Localizer.string("File no longer exists: %@"),
                name
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }
}
