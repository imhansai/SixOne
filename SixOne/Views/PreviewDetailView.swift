//
//  PreviewDetailView.swift
//  SixOne

import AppKit
import SwiftUI

/// 预览内容视图：顶栏 + 内容区；文本可内联编辑，文件按类型选渲染器，自身不带玻璃材质。
struct PreviewDetailView: View {
    let item: ClipboardItem
    let context: PanelContext
    var onItemEdited: (() -> Void)? = nil

    private var previewState: PreviewState { context.previewState }
    private var actions: PanelActionHandler? { context.actions }

    private let cornerRadius: CGFloat = 24

    @State private var metadata: PreviewMetadataModel
    @State private var shareAnchor = ViewAnchorBox()
    @State private var showsGroupFilePosition = false
    @State private var groupPositionRevealID = 0
    @State private var pathBarReachable = true

    init(item: ClipboardItem, context: PanelContext, onItemEdited: (() -> Void)? = nil) {
        self.item = item
        self.context = context
        self.onItemEdited = onItemEdited
        _metadata = State(initialValue: PreviewMetadataModel(
            item: item,
            previewState: context.previewState,
            manager: context.manager,
            textStatsCache: context.caches.textStats
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if isGroupListMode {
                PreviewGroupHeaderView(
                    item: item,
                    groupMeta: metadata.groupMeta,
                    shareAnchor: shareAnchor,
                    onRevealGroup: revealGroup
                )
            } else {
                PreviewHeaderView(
                    item: item,
                    subtitle: subtitle,
                    fileNameTitle: fileNameTitle,
                    linkOrigin: linkOrigin,
                    fileURL: fileURL,
                    linkURL: linkURL,
                    isGroupFileView: isGroupFileView
                )
            }

            VStack(spacing: ClipboardLayout.pathBarSpacing) {
                ZStack {
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 只裁到内容区，避免图片/QuickLook/PDF 画出边界盖住顶栏。
                .clipped()
                .overlay(alignment: .bottom) {
                    if showsGroupFilePosition, let position = groupFilePosition {
                        GroupFilePositionBadge(position: position.position, total: position.total)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                            .task(id: groupPositionRevealID) {
                                try? await Task.sleep(for: .seconds(PanelTiming.groupPositionHint))
                                guard !Task.isCancelled else { return }
                                withAnimation(.easeIn(duration: 0.25)) {
                                    showsGroupFilePosition = false
                                }
                            }
                    }
                }

                if let pathBarLocation {
                    FilePathBar(
                        location: pathBarLocation,
                        isReachable: pathBarReachable,
                        onCopy: { context.copyText($0) },
                        onPaste: { actions?.panelDidRequestPasteItem() }
                    )
                }
            }
            .padding(isGroupListMode ? 0 : ClipboardLayout.previewInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .task(id: metadataTaskID) {
            metadata.refreshFileMetadata(fileURL: fileURL, groupURLs: groupURLs)
            refreshPathBarReachability()
            revealGroupFilePosition()
        }
        .task(id: item.id) {
            await metadata.loadImageIfNeeded()
        }
        .task(id: metadata.textStatsTaskID) {
            await metadata.loadTextStats()
        }
    }

    // MARK: - 状态

    private var isGroupListMode: Bool {
        item.kind == .file && item.fileCount > 1 && !isGroupFileView
    }

    private var isGroupFileView: Bool {
        guard item.kind == .file, item.fileCount > 1,
              let index = previewState.groupFileIndex else { return false }
        return groupURLs.indices.contains(index)
    }

    /// 条目或组内下标变化时重新补齐元数据；替代原来的 onAppear + onChange 双份。
    private var metadataTaskID: String {
        "\(item.id.uuidString)-\(previewState.groupFileIndex.map(String.init) ?? "overview")"
    }

    // MARK: - 标题与副标题

    private var linkOrigin: String? {
        guard item.kind == .link else { return nil }
        return LinkPreview.origin(of: item.text)
    }

    private var fileNameTitle: String? {
        if item.kind == .file, item.fileCount > 1 {
            return isGroupFileView ? fileLocation?.name : nil
        }
        guard item.fileCount <= 1, item.kind == .file || item.kind == .image else { return nil }
        return fileLocation?.name
    }

    private var groupFilePosition: (position: Int, total: Int)? {
        guard isGroupFileView else { return nil }
        return previewState.viewingGroupFilePosition
    }

    /// 进入或切换组内文件时浮出位置。
    private func revealGroupFilePosition() {
        groupPositionRevealID += 1
        guard groupFilePosition != nil else {
            showsGroupFilePosition = false
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            showsGroupFilePosition = true
        }
    }

    private var subtitle: String? {
        switch item.kind {
        case .text, .link:
            // 统计在后台缓存，未就绪先不显示，避免 body 内 O(n) 扫描。
            return PreviewSubtitle.text(metadata.textStats)
        case .image:
            return PreviewSubtitle.image(metadata.image)
        case .file:
            if item.fileCount > 1 {
                if isGroupFileView { return PreviewSubtitle.file(metadata.fileMeta) }
                return PreviewSubtitle.group(count: item.fileCount, meta: metadata.groupMeta)
            }
            return PreviewSubtitle.file(metadata.fileMeta)
        case .color:
            return ColorPreview.subtitle(forColorData: item.colorData)
        }
    }

    // MARK: - 打开 / 在访达中显示

    /// 预览文件 URL：优先 bookmark 解析结果，组内单文件取当前项。
    private var fileURL: URL? {
        if item.kind == .file, item.fileCount > 1 {
            guard let index = previewState.groupFileIndex, groupURLs.indices.contains(index) else { return nil }
            return groupURLs[index]
        }
        return previewState.scopedFileURL?.url ?? (item.filePath.map(URL.init(fileURLWithPath:)))
    }

    /// 组内可访问 URL，与 allFilePaths 一一对应；nil 表示失联。
    private var groupURLs: [URL?] {
        item.fileCount > 1 ? previewState.scopedGroupURLs.map { $0?.url } : []
    }

    private var fileLocation: FileLocation? {
        FileLocation.make(
            paths: item.allFilePaths,
            scopedFileURL: previewState.scopedFileURL?.url,
            groupURLs: groupURLs,
            groupFileIndex: previewState.groupFileIndex
        )
    }

    /// 组总览不显示，其余有源文件的条目显示。
    private var pathBarLocation: FileLocation? {
        guard !isGroupListMode else { return nil }
        return fileLocation
    }

    /// 失联标记只在进入预览或切换组内项时更新。
    private func refreshPathBarReachability() {
        guard let location = pathBarLocation else {
            pathBarReachable = true
            return
        }
        let url: URL? = if item.kind == .file, item.fileCount > 1,
                           let index = previewState.groupFileIndex,
                           groupURLs.indices.contains(index) {
            groupURLs[index]
        } else {
            previewState.scopedFileURL?.url
        }
        pathBarReachable = FileManager.default.fileExists(atPath: url?.path ?? location.path)
    }

    private func revealGroup() {
        let urls = groupURLs.compactMap { $0 }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        actions?.panelDidHandOffToExternalApp()
    }

    private var linkURL: URL? {
        guard item.kind == .link, let text = item.text else { return nil }
        let url = URL(string: text)
        return url?.scheme != nil ? url : nil
    }

    nonisolated static func isWebScheme(_ scheme: String?) -> Bool {
        PreviewLinkOpenButton.isWebScheme(scheme)
    }

    // MARK: - 内容分发

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            TextPreviewView(
                // 指纹只取 O(1) 规模字段，避免在每次 body 求值做 O(n) 扫描。
                contentID: "\(item.id.uuidString)-\(item.text?.utf8.count ?? 0)-\(item.attributedTextData?.count ?? 0)",
                attributedTextData: item.attributedTextData,
                plainText: item.text,
                showsFormatting: previewState.showsFormatting,
                isEditable: previewState.isEditing,
                commitsOnExit: previewState.shouldCommitEditing,
                onEditingFinished: { finishEditing($0) },
                onDirtyChange: { previewState.hasUnsavedChanges = $0 },
                saveRequestID: previewState.saveRequestID,
                onCopyFallback: { [weak actions] in actions?.panelDidRequestCopyItem() },
                onPasteFallback: { [weak actions] in actions?.panelDidRequestPasteItem() },
                onEscape: { [weak actions] in actions?.panelDidRequestEscape() }
            )
        case .image:
            if let previewImage = metadata.image {
                InteractiveImagePreview(identity: item.id.uuidString, tier: previewImage.tier) { maxPixelSize in
                    await metadata.finerImage(maxPixelSize: maxPixelSize)
                }
            } else if metadata.imageLoadFailed {
                PreviewUnavailable()
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        case .file:
            if item.fileCount > 1 {
                FileGroupContent(
                    item: item,
                    groupURLs: groupURLs
                )
            } else if let scoped = previewState.scopedFileURL?.url.path ?? item.filePath {
                FilePreviewContent(url: URL(fileURLWithPath: scoped))
            } else {
                PreviewUnavailable()
            }
        case .link:
            LinkPreview(
                urlString: item.text,
                isEditable: previewState.isEditing,
                commitsOnExit: previewState.shouldCommitEditing,
                onEditingFinished: { finishEditing($0) },
                onDirtyChange: { previewState.hasUnsavedChanges = $0 },
                saveRequestID: previewState.saveRequestID
            )
        case .color:
            ColorPreview(colorData: item.colorData)
        }
    }

    // MARK: - 编辑提交

    /// 编辑完成：经 ClipboardManager 写回条目与剪贴板；视图不直接改模型。
    private func finishEditing(_ content: NSAttributedString) {
        context.saveEditedText(
            id: item.id,
            text: content.string,
            richText: TextPreviewView.rtfData(from: content)
        )
        metadata.invalidateTextStats()
        onItemEdited?()
    }
}
