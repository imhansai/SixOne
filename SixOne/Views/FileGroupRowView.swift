//
//  FileGroupRowView.swift
//  SixOne
//  组内单行：缩略图/文件图标、名称与大小、复制反馈与右键菜单。
//

import AppKit
import Observation
import SwiftUI

/// 行内异步状态，按组内原始下标复用（筛选/单元格复用时保留）。
@Observable
final class FileGroupRowState {
    var thumbnail: NSImage?
    var isDirectory = false
    var size: Int64?
    var isCopied = false
    private var copyFeedbackID = 0
    private var loadedPath: String?

    func load(file: GroupFileEntry, cache: FileGroupThumbnailCache, displayScale: CGFloat) async {
        let path = file.url?.path ?? file.path
        if loadedPath != path {
            loadedPath = path
            thumbnail = nil
            isCopied = false
        }
        let values = try? URL(fileURLWithPath: path).resourceValues(
            forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey]
        )
        let directory = values?.isDirectory ?? false
        isDirectory = directory
        size = values?.fileSize.map(Int64.init)
        guard let url = file.url, !directory else {
            thumbnail = nil
            return
        }
        // 修改时间 + 大小进缓存键，同路径内容变化可拿到新图。
        let version = (values?.contentModificationDate?.timeIntervalSince1970 ?? 0) + Double(values?.fileSize ?? 0)
        let image = await cache.thumbnail(
            for: url,
            pointSize: ClipboardLayout.groupRowThumbnailSize,
            scale: displayScale,
            version: version
        )
        guard !Task.isCancelled else { return }
        thumbnail = image
    }

    func markCopied() {
        copyFeedbackID += 1
        let feedbackID = copyFeedbackID
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PanelTiming.copiedFeedback) { [weak self] in
            guard let self, self.copyFeedbackID == feedbackID else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isCopied = false
            }
        }
    }
}

/// 组内一行，视觉对齐 ClipboardRowView；首末行留白折进行高。
struct FileGroupRow: View {
    let file: GroupFileEntry
    let state: FileGroupRowState
    let rowID: UUID
    let clickTracker: RowClickTracker
    /// 快速粘贴编号。
    var shortcutNumber: Int? = nil
    let isSelected: Bool
    let isListActive: Bool
    let sourceAppBundleIdentifier: String?
    let thumbnailCache: FileGroupThumbnailCache
    let displayScale: CGFloat
    var listTopPadding: CGFloat = 0
    var listBottomPadding: CGFloat = 0
    let onSelect: (Int) -> Void
    let onPreview: (Int) -> Void
    let onCommand: (GroupFileCommand, Int) -> Void
    let onShare: (Int, NSView) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(PanelContext.self) private var context

    private var index: Int { file.index }
    private var url: URL? { file.url }
    private var name: String { file.name }
    private var currentPath: String { url?.path ?? file.path }

    private var iconShadowColor: Color {
        RowAppearance.iconShadowColor(for: colorScheme)
    }

    var body: some View {
        ListRowShell(
            rowID: rowID,
            isSelected: isSelected,
            isListActive: isListActive,
            listTopPadding: listTopPadding,
            listBottomPadding: listBottomPadding,
            shortcutNumber: shortcutNumber,
            isCopied: state.isCopied,
            title: name,
            titleTooltipDetail: titleTooltipDetail,
            subtitle: AnyView(Text(detailText)),
            onCopy: copyFile,
            onSelect: { _ in onSelect(index) },
            onActivate: { _, _ in onCommand(.paste, index) },
            makeMenu: { host in menu(for: host) },
            clickTracker: clickTracker
        ) {
            leadingIcon
        }
        // 内容变化时重跑；迟到的缩略图由取消丢弃。
        .task(id: file) {
            await state.load(file: file, cache: thumbnailCache, displayScale: displayScale)
        }
        // 复制反馈由控制器统一发回，按钮、菜单与 ⌘C 都会闪对勾。
        .onChange(of: context.previewState.groupCopyFeedbackRevision) { _, _ in
            guard context.previewState.groupCopyFeedbackIndex == index else { return }
            state.markCopied()
        }
    }

    private func menu(for host: RowInteractionHost.HostView) -> NSMenu {
        onSelect(index)
        return FileGroupMenuBuilder.makeMenu(
            target: host,
            isReachable: url != nil,
            onPreview: { onPreview(index) },
            onPaste: { onCommand(.paste, index) },
            onCopy: { copyFile() },
            onShare: { onShare(index, $0) },
            onOpen: { onCommand(.open, index) },
            onReveal: { onCommand(.reveal, index) }
        )
    }

    private func copyFile() {
        onCommand(.copy, index)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            if let thumbnail = state.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .shadow(color: iconShadowColor, radius: 3, y: 1)
            } else if let icon = fileIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 38, height: 38)
                    .shadow(color: iconShadowColor, radius: 3, y: 1)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            sourceBadge
        }
    }

    private var fileIcon: NSImage? {
        context.caches.preview.image(for: "file-\(currentPath)") {
            NSWorkspace.shared.icon(forFile: currentPath)
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if let bundleID = sourceAppBundleIdentifier,
           let appURL = context.caches.query.appURL(for: bundleID) {
            Image(nsImage: context.caches.preview.image(for: "app-\(bundleID)") {
                NSWorkspace.shared.icon(forFile: appURL.path)
            } ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: iconShadowColor, radius: 2, y: 1)
                .offset(x: 4, y: 4)
        }
    }

    private var detailText: String {
        guard url != nil else { return "—" }
        if state.isDirectory { return Localizer.string("Folder") }
        guard let size = state.size else { return "" }
        return ByteCountFormatting.string(fromByteCount: size)
    }

    private var titleTooltipDetail: String {
        if let url { return url.path }
        return String(format: Localizer.string("File no longer exists: %@"), name)
    }
}
