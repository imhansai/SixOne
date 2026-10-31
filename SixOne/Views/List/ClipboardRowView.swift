//
//  ClipboardRowView.swift
//  SixOne
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 行视图

/// 单行内容（HistoryRow 轻量快照）：选中态与复制反馈都按值注入。
struct ClipboardRowView: View {
    let row: HistoryRow
    /// 按住 ⌘ 时的快速粘贴编号；不显示时为空。
    var shortcutNumber: Int? = nil
    let isSelected: Bool
    let isListActive: Bool
    /// 复制反馈由表格按行值传入，避免每行都观察全局反馈。
    var isCopied = false
    /// 首末行额外让出的列表留白，算在行内并随内容滚动。
    var listTopPadding: CGFloat = 0
    var listBottomPadding: CGFloat = 0
    /// 单击选中，参数是按下时的条目 id（抬起时视图可能已被复用）。
    let onSelect: (UUID) -> Void
    /// 双击激活：连击起点的条目 id，以及按住 ⇧ 的纯文本意图。
    let onActivate: (UUID, Bool) -> Void
    let onCopy: () -> Void
    let menuProvider: (RowInteractionHost.HostView) -> NSMenu?
    var clickTracker: RowClickTracker?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(PanelContext.self) private var context

    private var iconShadowColor: Color {
        RowAppearance.iconShadowColor(for: colorScheme)
    }

    var body: some View {
        ListRowShell(
            rowID: row.id,
            isSelected: isSelected,
            isListActive: isListActive,
            listTopPadding: listTopPadding,
            listBottomPadding: listBottomPadding,
            shortcutNumber: shortcutNumber,
            isCopied: isCopied,
            title: titleText,
            titleTooltipDetail: titleTooltipDetail,
            accessibilityDetail: accessibilityDetail,
            subtitle: AnyView(Text(subtitleText)),
            onCopy: onCopy,
            onSelect: onSelect,
            onActivate: onActivate,
            makeMenu: menuProvider,
            clickTracker: clickTracker
        ) {
            leadingIcon
        }
        // 旧尺寸缩略图在行第一次出现时按当前尺寸重算；只处理已有缩略图的条目。
        .task(id: row.id) {
            guard row.thumbnailData != nil,
                  row.thumbnailVersion != ClipboardItem.currentThumbnailVersion else { return }
            context.actions?.panelDidRequestThumbnailRefresh(id: row.id)
        }
    }

    private var titleTooltipDetail: String? {
        guard row.kind == .file || row.kind == .image,
              let path = row.filePath,
              !path.isEmpty else { return nil }
        return path
    }

    private enum RowType {
        case text
        case image(contentType: String)
        case singleFile(isFolder: Bool)
        case fileGroup(count: Int, firstName: String)
        case link
        case color
    }

    private var rowType: RowType {
        switch row.kind {
        case .text:
            return .text
        case .image:
            return .image(contentType: row.contentType?.uppercased() ?? "")
        case .file:
            if row.fileCount > 1 {
                let name = row.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
                return .fileGroup(count: row.fileCount, firstName: name)
            }
            let isFolder = row.filePath.map { context.caches.query.fileKind(atPath: $0) == .folder } ?? false
            return .singleFile(isFolder: isFolder)
        case .link:
            return .link
        case .color:
            return .color
        }
    }

    /// 行标题：文件组按当前语言现算（快照会锁住旧文案），其余优先用快照。
    private var titleText: String {
        if case .fileGroup = rowType { return fallbackTitle }
        if let title = row.title, !title.isEmpty {
            return title
        }
        return fallbackTitle
    }

    private var fallbackTitle: String {
        switch rowType {
        case .text:
            return Localizer.string("Text")
        case .image(let contentType):
            return contentType.isEmpty
                ? Localizer.string("Image")
                : String(format: Localizer.string("%@ image"), contentType)
        case .singleFile(let isFolder):
            return Localizer.string(isFolder ? "Folder" : "File")
        case .fileGroup(let count, let firstName):
            return Localizer.groupTitle(firstName: firstName, count: count)
        case .link:
            return Localizer.string("Link")
        case .color:
            return Localizer.string("Color")
        }
    }

    private var copyTime: String {
        context.caches.time.copyTime(
            for: row.id,
            lastActivityAt: row.lastActivityAt,
            locale: locale
        )
    }

    private var subtitleText: LocalizedStringKey {
        "\(typeLabelKey) · copied at \(copyTime)"
    }

    private var accessibilityDetail: String {
        var resource = typeLabelKey
        resource.locale = RuntimeLanguage.shared.locale
        return "\(String(localized: resource)), \(copyTime)"
    }

    private var typeLabelKey: LocalizedStringResource {
        switch rowType {
        case .text:
            return "Text"
        case .image(let contentType):
            return contentType.isEmpty ? "Image" : "\(contentType) image"
        case .singleFile(let isFolder):
            return isFolder ? "Folder" : "File"
        case .fileGroup(let count, _):
            return "\(String(count)) items"
        case .link:
            return "Link"
        case .color:
            return "Color"
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch row.kind {
        case .image:
            ZStack(alignment: .bottomTrailing) {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .shadow(color: iconShadowColor, radius: 3, y: 1)
                } else {
                    systemIcon("photo")
                }
                sourceBadge
            }
        case .file:
            ZStack(alignment: .bottomTrailing) {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .shadow(color: iconShadowColor, radius: 3, y: 1)
                } else if let path = row.filePath {
                    Image(nsImage: context.caches.preview.image(for: "file-\(path)", loader: { NSWorkspace.shared.icon(forFile: path) }) ?? NSImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 38, height: 38)
                        .shadow(color: iconShadowColor, radius: 3, y: 1)
                } else {
                    systemIcon("doc")
                }
                sourceBadge
            }
            .overlay(alignment: .bottomLeading) { fileCountBadge }
        case .text:
            ZStack(alignment: .bottomTrailing) {
                textFileIcon
                sourceBadge
            }
        case .link:
            ZStack(alignment: .bottomTrailing) {
                linkIcon
                sourceBadge
            }
        case .color:
            ZStack(alignment: .bottomTrailing) {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: iconShadowColor, radius: 3, y: 1)
                } else {
                    systemIcon("paintpalette")
                }
                sourceBadge
            }
        }
    }

    @ViewBuilder
    private var textFileIcon: some View {
        if let icon = context.caches.preview.image(
            for: "type-plain-text",
            loader: { NSWorkspace.shared.icon(for: .plainText) }
        ) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 38, height: 38)
                .shadow(color: iconShadowColor, radius: 3, y: 1)
        } else {
            systemIcon("doc.text")
        }
    }

    /// 链接没有缩略图，用纸片卡片对齐其他文档图标的体积。
    private var linkIcon: some View {
        Image(systemName: "link")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.secondary)
            .frame(width: 38, height: 38)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: iconShadowColor, radius: 3, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
    }

    private var thumbnail: NSImage? {
        guard let data = row.thumbnailData else { return nil }
        return context.caches.preview.image(for: "thumb-\(row.id.uuidString)") {
            NSImage(data: data)
        }
    }

    private func systemIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 24, weight: .light))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if let bundleID = row.sourceAppBundleIdentifier,
           let appURL = context.caches.query.appURL(for: bundleID) {
            Image(nsImage: context.caches.preview.image(for: "app-\(bundleID)", loader: { NSWorkspace.shared.icon(forFile: appURL.path) }) ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: iconShadowColor, radius: 2, y: 1)
                .offset(x: 4, y: 4)
        }
    }

    @ViewBuilder
    private var fileCountBadge: some View {
        if row.fileCount > 1 {
            Text("\(row.fileCount)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.horizontal, 5)
                .frame(height: 15)
                .background(Capsule().fill(Color.accentColor))
                .overlay(
                    Capsule().strokeBorder(
                        colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.9),
                        lineWidth: 1
                    )
                )
                .offset(x: -2, y: 2)
        }
    }
}

