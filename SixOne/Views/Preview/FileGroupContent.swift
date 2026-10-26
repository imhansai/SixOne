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
    private var actions: PanelActionHandler? { context.actions }

    var body: some View {
        let viewingIndex = viewingGroupFileIndex
        return ZStack {
            FileGroupPreview(
                context: context,
                files: visibleGroupEntries,
                isListActive: !previewState.isGroupFilterFocused,
                sourceAppBundleIdentifier: item.sourceAppBundleIdentifier,
                selectedIndex: previewState.groupSelectedIndex,
                thumbnailCache: context.caches.fileGroupThumbnails,
                scrollRequest: previewState.groupScrollRequest,
                scrollRequestID: previewState.groupScrollRequestID,
                isScrollBlocked: context.confirmationState.isPresenting,
                onSelect: { index in
                    previewState.selectGroupFile(index)
                    // 收回键盘焦点，让方向键与裸 ⌫ 仍可用。
                    actions?.panelDidRequestFocusContent()
                },
                onPreview: { previewState.showGroupFile($0) },
                onCommand: handleGroupFileCommand,
                onShare: { index, anchorView in
                    actions?.panelDidRequestGroupFileShare(at: index, anchorView: anchorView)
                }
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
                        missingGroupFileNotice(index: index)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var viewingGroupFileIndex: Int? {
        guard let index = previewState.groupFileIndex, groupURLs.indices.contains(index) else { return nil }
        return index
    }

    /// 组内文件动作：打开与访达在此处理，粘贴/拷贝交给面板。
    private func handleGroupFileCommand(_ command: GroupFileCommand, index: Int) {
        switch command {
        case .open:
            if groupURLs.indices.contains(index), let url = groupURLs[index] { openGroupFile(url) }
        case .reveal:
            if groupURLs.indices.contains(index), let url = groupURLs[index] { revealInFinder(url) }
        case .paste, .copy:
            actions?.panelDidInvokeGroupFileCommand(command, index: index)
        }
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        actions?.panelDidHandOffToExternalApp()
    }

    private func missingGroupFileNotice(index: Int) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(String(
                format: Localizer.string("File no longer exists: %@"),
                groupEntries[index].name
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    /// 列表数据：路径与 URL 成对，下标对齐由本视图保证。
    private var groupEntries: [GroupFileEntry] {
        item.allFilePaths.enumerated().map { index, path in
            GroupFileEntry(
                index: index,
                path: path,
                url: groupURLs.indices.contains(index) ? groupURLs[index] : nil
            )
        }
    }

    /// 筛选后的行；GroupFileEntry.index 始终是组内原始下标。
    private var visibleGroupEntries: [GroupFileEntry] {
        let entries = groupEntries
        return previewState.visibleGroupFileIndices.compactMap { index in
            entries.indices.contains(index) ? entries[index] : nil
        }
    }

    private func openGroupFile(_ url: URL) {
        NSWorkspace.shared.open(url)
        actions?.panelDidHandOffToExternalApp()
    }
}
