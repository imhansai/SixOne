//
//  PreviewDetailView.swift
//  SixOne

import AppKit
import SwiftUI

/// 主标题后的复制按钮。
struct PreviewHeaderCopy {
    let text: String
    let help: String
}

enum PreviewHeaderCopyAction {
    @MainActor
    static func make(
        for item: ClipboardItem,
        isEditing: Bool,
        fileNameTitle: String?,
        linkOrigin: String?
    ) -> PreviewHeaderCopy? {
        guard !isEditing else { return nil }
        switch item.kind {
        case .text:
            guard let text = item.text, !text.isEmpty else { return nil }
            return PreviewHeaderCopy(text: text, help: Localizer.string("Copy Text"))
        case .image, .file:
            guard let fileNameTitle, !fileNameTitle.isEmpty else { return nil }
            return PreviewHeaderCopy(text: fileNameTitle, help: Localizer.string("Copy File Name"))
        case .link:
            if let linkOrigin {
                return PreviewHeaderCopy(text: linkOrigin, help: Localizer.string("Copy Origin"))
            }
            // 无 host 的链接，复制地址本身。
            guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return PreviewHeaderCopy(text: text, help: Localizer.string("Copy Link"))
        case .color:
            guard let hex = item.colorHexString else { return nil }
            return PreviewHeaderCopy(text: hex, help: Localizer.string("Copy Hex Value"))
        }
    }
}

/// 预览顶栏主标题：各类型都尽量给出内容身份，而不是类别名。
enum PreviewHeaderTitle {
    @MainActor
    static func mainTitle(
        for item: ClipboardItem,
        isEditing: Bool,
        fileNameTitle: String?,
        linkOrigin: String?
    ) -> String {
        if isEditing { return Localizer.string("Edit") }
        switch item.kind {
        case .text, .color:
            // 文本取首行、颜色取色值，比类别名更能辨认。
            return item.displayTitle
        case .image, .file:
            return fileNameTitle ?? item.displayTitle
        case .link:
            // 无 host 的链接（mailto: 等）用地址本身。
            return linkOrigin ?? item.displayTitle
        }
    }
}

/// 预览内容视图：顶栏标题 + 内容区；文本可内联编辑，文件按类型选渲染器，自身不带玻璃材质。
struct PreviewDetailView: View {
    let item: ClipboardItem
    var onItemEdited: (() -> Void)? = nil

    @Environment(PanelContext.self) private var context

    private var manager: ClipboardManager { context.manager }
    private var previewState: PreviewState { context.previewState }
    private var actions: PanelActionHandler? { context.actions }

    private let cornerRadius: CGFloat = 24

    @State private var previewImage: PreviewImage?
    @State private var previewImageData: Data?
    @State private var imageLoadFailed = false
    @State private var defaultApp: URL?
    @State private var availableApps: [URL] = []
    @State private var fileMeta: (size: Int64?, modDate: Date?, isDirectory: Bool)?
    @State private var groupMeta: GroupMeta?
    @State private var shareAnchor = ViewAnchorBox()
    @State private var textStats: TextStats?
    @State private var statsRevision = 0
    @State private var showsGroupFilePosition = false
    @State private var groupPositionRevealID = 0
    @State private var pathBarReachable = true
    var body: some View {
        VStack(spacing: 0) {
            if isGroupListMode {
                groupListHeader
            } else {
                previewHeader
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
                        onCopy: { manager.copyPlainText($0) },
                        onPaste: { actions?.panelDidRequestPasteItem() }
                    )
                }
            }
            .padding(isGroupListMode ? 0 : ClipboardLayout.previewInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .onAppear {
            ensureMetadata()
            refreshPathBarReachability()
            revealGroupFilePosition()
        }
        .onChange(of: previewState.groupFileIndex) { _, _ in
            ensureMetadata()
            refreshPathBarReachability()
            defaultApp = nil
            availableApps = []
            loadOpenWithApps()
            revealGroupFilePosition()
        }
        .task(id: item.id) {
            await loadPreviewImage()
        }
        .task(id: textStatsTaskID) {
            guard item.kind == .text || item.kind == .link, let text = item.text else { return }
            textStats = await context.caches.textStats.stats(for: item.id, text: text)
        }
    }

    // MARK: - 顶栏

    private var isGroupListMode: Bool {
        item.kind == .file && item.fileCount > 1 && !isGroupFileView
    }

    private var isGroupFileView: Bool {
        guard item.kind == .file, item.fileCount > 1,
              let index = previewState.groupFileIndex else { return false }
        return groupURLs.indices.contains(index)
    }

    private var groupListHeader: some View {
        PanelHeaderChrome {
            HStack(spacing: 12) {
                ZStack {
                    Image(systemName: "square.3.layers.3d.down.left")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(width: 44, height: 44)
                .allowsHitTesting(false)

                groupFilterField
                    .frame(maxWidth: .infinity)

                groupInfoStack

                groupActions
            }
        }
    }

    private var groupActions: some View {
        HStack(spacing: ClipboardLayout.headerActionSpacing) {
            PreviewHeaderActionButton(
                systemImage: "square.and.arrow.up",
                help: Localizer.string("Share")
            ) {
                actions?.panelDidRequestShareGroup(anchorView: shareAnchor.view)
            }
            .background(ViewAnchor(box: shareAnchor))

            PreviewHeaderActionButton(
                systemImage: "folder",
                help: Localizer.string("Reveal in Finder")
            ) {
                revealGroup()
            }

            PreviewHeaderActionButton(
                systemImage: "xmark",
                help: Localizer.string("Close Preview")
            ) {
                previewState.close()
            }
        }
    }

    private var groupFilterField: some View {
        SearchField(
            text: previewState.groupFilterText,
            placeholder: Localizer.string("Search Files in Group"),
            focusRequestID: previewState.groupFilterFocusRequestID,
            blurRequestID: previewState.groupFilterBlurRequestID,
            identifier: .groupFilterField,
            focusOnAppear: previewState.groupFilterNeedsFocus,
            onTextChange: { previewState.setGroupFilterText($0) },
            onFocusChange: { previewState.groupFilterFocusDidChange($0) },
            onCancel: {
                // 有词时清空并保持焦点，无词才退出到列表。
                let wasEmpty = previewState.groupFilterText.isEmpty
                previewState.cancelGroupFilter()
                if wasEmpty { actions?.panelDidRequestFocusContent() }
            },
            onMoveDown: {
                previewState.moveFromGroupFilterToList()
                actions?.panelDidRequestFocusContent()
            },
            onTab: { _ in
                previewState.moveFromGroupFilterToList()
                actions?.panelDidRequestFocusContent()
            }
        )
    }

    private var groupInfoStack: some View {
        VStack(alignment: .center, spacing: 1) {
            Text(groupCountText)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
            Text(groupSizeText ?? " ")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .opacity(groupSizeText == nil ? 0 : 1)
        }
        .fixedSize()
        .allowsHitTesting(false)
    }

    private var groupCountText: String {
        let count = String(format: Localizer.string("%@ items"), String(item.fileCount))
        guard let groupMeta, groupMeta.missingCount > 0 else { return count }
        return "\(count) · \(String(format: Localizer.string("%@ missing"), String(groupMeta.missingCount)))"
    }

    private var groupSizeText: String? {
        guard let groupMeta, groupMeta.totalSize > 0 else { return nil }
        return ByteCountFormatting.string(fromByteCount: groupMeta.totalSize)
    }

    private var previewHeader: some View {
        let subtitleText = subtitle
        return PanelHeaderChrome {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mainTitle)
                            .font(.system(size: 20, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(titleTruncationMode)
                            // 文字不参与命中，留出拖动面板的区域。
                            .allowsHitTesting(false)
                            .appTooltipIf(item.kind == .link, text: linkOrigin ?? mainTitle)
                        if let titleCopy {
                            CopyTextButton(
                                text: titleCopy.text,
                                help: titleCopy.help
                            ) { text in
                                manager.copyPlainText(text)
                            }
                        }
                    }
                    // 副标题始终占位，避免撤行时主标题跳位；编辑态用 opacity 隐去，VoiceOver 一并忽略。
                    Text(subtitleText ?? " ")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(previewState.isEditing || subtitleText == nil ? 0 : 1)
                        .accessibilityHidden(previewState.isEditing || subtitleText == nil)
                        .allowsHitTesting(false)
                }
                .padding(.leading, ClipboardLayout.previewTitleInset)
                Spacer()

                HStack(spacing: ClipboardLayout.headerActionSpacing) {
                    // 显示格式开关仅只读态出现，编辑态隐去但占位。
                    if item.kind == .text, item.attributedTextData != nil {
                        formattingToggleButton
                            .opacity(previewState.isEditing ? 0 : 1)
                            .allowsHitTesting(!previewState.isEditing)
                    }
                    if item.kind == .link, linkURL != nil {
                        openLinkButton
                    } else if item.kind == .file, fileURL != nil {
                        openWithMenu
                    }
                    if item.kind == .text || item.kind == .link {
                        editToggleButton
                    }

                    closePreviewButton
                }
            }
        }
    }

    /// 只读态关闭预览；编辑态取消编辑；组内单文件态退回组列表。
    private var closePreviewButton: some View {
        PreviewHeaderActionButton(systemImage: "xmark", help: closeButtonHelp) {
            if previewState.isEditing {
                // 有改动时由面板先弹确认，不能直接丢弃。
                if let actions {
                    actions.panelDidRequestCancelEditing()
                } else {
                    previewState.cancelEditing()
                }
            } else if isGroupFileView {
                previewState.showGroupOverview()
            } else {
                previewState.close()
            }
        }
    }

    private var closeButtonHelp: String {
        if previewState.isEditing { return Localizer.string("Cancel Editing") }
        if isGroupFileView { return Localizer.string("All Files") }
        return Localizer.string("Close Preview")
    }

    // MARK: - 数据补齐

    private var textStatsTaskID: String {
        "\(item.id.uuidString)-\(statsRevision)"
    }

    /// 图片条目按 id 补齐 imageData 并解码（列表查询不含大字段）。
    private func loadPreviewImage() async {
        guard item.kind == .image, previewImage == nil else { return }
        let full = item.imageData == nil ? manager.fetchFullItem(id: item.id) : item
        guard let data = full?.imageData else {
            imageLoadFailed = true
            return
        }
        let tier = await PreviewImageDecoder.decode(data, maxPixelSize: ClipboardLayout.previewImageBasePixelSize)
        // 可能已切走/关闭预览，迟到结果丢弃。
        guard !Task.isCancelled, previewImage == nil else { return }
        guard let tier else {
            imageLoadFailed = true
            return
        }
        previewImageData = data
        previewImage = PreviewImage(tier: tier, byteCount: data.count)
    }

    private func loadFinerPreviewImage(maxPixelSize: Int) async -> PreviewImageDecoder.Tier? {
        guard let previewImageData else { return nil }
        return await PreviewImageDecoder.decode(previewImageData, maxPixelSize: maxPixelSize)
    }

    /// 读取并缓存文件元数据；组元数据后台计算，避免上百文件 stat 卡主线程。
    private func ensureMetadata() {
        guard item.kind == .file else { return }
        if item.fileCount > 1 {
            if groupMeta == nil {
                let itemID = item.id
                let urls = groupURLs
                Task {
                    let meta = await Self.groupMeta(for: urls)
                    guard previewState.item?.id == itemID else { return }
                    groupMeta = meta
                }
            }
            refreshGroupFileMeta()
            return
        }
        guard let fileURL, fileMeta == nil else { return }
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
        fileMeta = (
            values?.fileSize.map(Int64.init),
            values?.contentModificationDate,
            values?.isDirectory ?? false
        )
    }

    private func refreshGroupFileMeta() {
        guard let index = previewState.groupFileIndex,
              groupURLs.indices.contains(index),
              let url = groupURLs[index] else {
            fileMeta = nil
            return
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
        fileMeta = (
            values?.fileSize.map(Int64.init),
            values?.contentModificationDate,
            values?.isDirectory ?? false
        )
    }

    /// 组元数据：按解析后 URL 统计非目录文件大小，避免移动后少算。
    private nonisolated static func groupMeta(for urls: [URL?]) async -> GroupMeta {
        var totalSize: Int64 = 0
        var missingCount = 0
        for url in urls {
            guard let url else {
                missingCount += 1
                continue
            }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            guard let size = values?.fileSize, values?.isDirectory != true else { continue }
            totalSize += Int64(size)
        }
        return GroupMeta(totalSize: totalSize, missingCount: missingCount)
    }

    // MARK: - 标题与副标题

    private var mainTitle: String {
        PreviewHeaderTitle.mainTitle(
            for: item,
            isEditing: previewState.isEditing,
            fileNameTitle: fileNameTitle,
            linkOrigin: linkOrigin
        )
    }

    /// 主标题旁的复制按钮。
    private var titleCopy: PreviewHeaderCopy? {
        PreviewHeaderCopyAction.make(
            for: item,
            isEditing: previewState.isEditing,
            fileNameTitle: fileNameTitle,
            linkOrigin: linkOrigin
        )
    }

    /// 文本尾部截断；文件名与链接中间截断。
    private var titleTruncationMode: Text.TruncationMode {
        item.kind == .text ? .tail : .middle
    }

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
            guard let textStats else { return nil }
            return String(
                format: Localizer.string("%@ characters · %@ words · %@ lines"),
                Self.groupedCount(textStats.characters),
                Self.groupedCount(textStats.words),
                Self.groupedCount(textStats.lines)
            )
        case .image:
            guard let previewImage else { return nil }
            let size = previewImage.tier.displaySize
            let sizeText = "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
            return "\(sizeText) · \(ByteCountFormatting.string(fromByteCount: Int64(previewImage.byteCount)))"
        case .file:
            if item.fileCount > 1 {
                if isGroupFileView { return fileSubtitle }
                var parts = [String(format: Localizer.string("%@ items"), String(item.fileCount))]
                if let groupMeta {
                    if groupMeta.totalSize > 0 {
                        parts.append(ByteCountFormatting.string(fromByteCount: groupMeta.totalSize))
                    }
                    if groupMeta.missingCount > 0 {
                        parts.append(String(format: Localizer.string("%@ missing"), String(groupMeta.missingCount)))
                    }
                }
                return parts.joined(separator: " · ")
            }
            return fileSubtitle
        case .color:
            return ColorPreview.subtitle(forColorData: item.colorData)
        }
    }

    private var fileSubtitle: String? {
        guard let fileMeta else { return nil }
        let dateText = fileMeta.modDate?.formattedAbsolute
        if fileMeta.isDirectory {
            guard let dateText else { return nil }
            return "\(Localizer.string("Folder")) · \(dateText)"
        }
        let sizeText = ByteCountFormatting.string(fromByteCount: fileMeta.size ?? 0)
        guard let dateText else { return sizeText }
        return "\(sizeText) · \(dateText)"
    }

    // MARK: - 顶栏按钮

    private var editToggleButton: some View {
        PreviewHeaderActionButton(
            systemImage: previewState.isEditing ? "checkmark" : "pencil",
            help: previewState.isEditing
                ? Localizer.string("Finish editing and save")
                : Localizer.string("Edit text")
        ) {
            if previewState.isEditing {
                // 置位「退出即落盘」再退出编辑态。
                previewState.finishEditing()
            } else {
                previewState.startEditing()
            }
        }
    }

    private var formattingToggleButton: some View {
        let titleKey: String.LocalizationValue = previewState.showsFormatting
            ? "Show Plain Text"
            : "Show Formatting"
        return PreviewHeaderActionButton(
            systemImage: previewState.showsFormatting ? "doc.plaintext" : "paintpalette",
            help: Localizer.string(titleKey)
        ) {
            previewState.showsFormatting.toggle()
        }
    }

    /// 按运行时语言给数字加千分位；模板用 %@ 而非 %d，才能跟随语言的分隔符。
    private static func groupedCount(_ value: Int) -> String {
        value.formatted(.number.locale(RuntimeLanguage.shared.locale))
    }

    // MARK: - 打开 / 在访达中显示

    /// 仿 QuickLook 菜单；应用列表仅首次出现时查询，避免反复枚举 LaunchServices。
    private var openWithMenu: some View {
        Menu {
            if let defaultApp {
                Button(String(format: Localizer.string("Open in %@"), defaultApp.displayName)) {
                    openIn(defaultApp)
                }
                Divider()
                ForEach(availableApps.filter { $0 != defaultApp }, id: \.self) { app in
                    Button(app.displayName) {
                        openIn(app)
                    }
                }
                Divider()
            } else {
                ForEach(availableApps, id: \.self) { app in
                    Button(app.displayName) {
                        openIn(app)
                    }
                }
                if !availableApps.isEmpty {
                    Divider()
                }
            }
            Button(Localizer.string("Reveal in Finder")) {
                revealInFinder()
            }
        } label: {
            PreviewHeaderMenuLabel(systemImage: "arrow.up.forward.app")
        }
        .buttonStyle(.plain)
        .appTooltip(Localizer.string("Open with"))
        .accessibilityLabel(Localizer.string("Open with"))
        .onAppear {
            loadOpenWithApps()
        }
    }

    private func loadOpenWithApps() {
        guard let fileURL else { return }
        if defaultApp == nil {
            defaultApp = NSWorkspace.shared.urlForApplication(toOpen: fileURL)
        }
        if availableApps.isEmpty {
            availableApps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
        }
    }

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

    private func openIn(_ app: URL) {
        guard let fileURL else { return }
        if let defaultApp, app == defaultApp {
            NSWorkspace.shared.open(fileURL)
        } else {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([fileURL], withApplicationAt: app, configuration: config) { _, error in
                if error != nil {
                    NSWorkspace.shared.open(fileURL)
                }
            }
        }
        actions?.panelDidHandOffToExternalApp()
    }

    private func revealInFinder() {
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        actions?.panelDidHandOffToExternalApp()
    }

    private var linkURL: URL? {
        guard item.kind == .link, let text = item.text else { return nil }
        let url = URL(string: text)
        return url?.scheme != nil ? url : nil
    }

    private var openLinkButton: some View {
        let isWeb = Self.isWebScheme(linkURL?.scheme)
        let titleKey: String.LocalizationValue = isWeb ? "Open in Browser" : "Open Link"
        return PreviewHeaderActionButton(
            systemImage: isWeb ? "safari" : "arrow.up.forward.app",
            help: Localizer.string(titleKey)
        ) {
            openLink()
        }
    }

    /// 打开链接；无处理程序时提示，不静默失败。
    private func openLink() {
        guard let url = linkURL else { return }
        guard NSWorkspace.shared.open(url) else {
            context.noticeState.message = String(
                format: Localizer.string("Cannot open link: %@"),
                url.absoluteString
            )
            return
        }
        actions?.panelDidHandOffToExternalApp()
    }

    nonisolated static func isWebScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
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
            if let previewImage {
                InteractiveImagePreview(identity: item.id.uuidString, tier: previewImage.tier) { maxPixelSize in
                    await loadFinerPreviewImage(maxPixelSize: maxPixelSize)
                }
            } else if imageLoadFailed {
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
        manager.updateEditedText(
            id: item.id,
            text: content.string,
            richText: TextPreviewView.rtfData(from: content)
        )
        context.caches.textStats.invalidate(for: item.id)
        statsRevision += 1
        onItemEdited?()
    }

    private struct PreviewImage {
        let tier: PreviewImageDecoder.Tier
        let byteCount: Int
    }

    private struct GroupMeta {
        let totalSize: Int64
        let missingCount: Int
    }
}

private struct GroupFilePositionBadge: View {
    let position: Int
    let total: Int

    var body: some View {
        Text("\(position) / \(total)")
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            .allowsHitTesting(false)
    }
}

private extension URL {
    /// 应用包路径的显示名（去掉 .app 后缀）。
    var displayName: String {
        var name = lastPathComponent
        if name.hasSuffix(".app") {
            name.removeLast(4)
        }
        return name
    }
}
