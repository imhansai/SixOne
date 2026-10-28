//
//  ClipboardRowView.swift
//  SixOne
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 行视图

/// 单行内容（HistoryRow 轻量快照）：选中态按值注入，复制反馈在行内观察。
struct ClipboardRowView: View {
    let row: HistoryRow
    /// 按住 ⌘ 时的快速粘贴编号；不显示时为空。
    var shortcutNumber: Int? = nil
    let isSelected: Bool
    let isListActive: Bool
    /// 首末行额外让出的列表留白，算在行内并随内容滚动。
    var listTopPadding: CGFloat = 0
    var listBottomPadding: CGFloat = 0
    /// 单击选中，参数是按下时的条目 id（抬起时视图可能已被复用）。
    let onSelect: (UUID) -> Void
    /// 双击激活，参数是连击序列起点的条目 id。
    let onActivate: (UUID) -> Void
    let onCopy: () -> Void
    let menuProvider: (RowInteractionHost.HostView) -> NSMenu?
    var clickTracker: RowClickTracker?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(PanelContext.self) private var context

    private var isActiveSelection: Bool { isSelected && isListActive }

    private var isCopied: Bool {
        context.copyState.feedbackItemID == row.id
    }

    private var usesOverlayScrollers: Bool {
        context.scrollerLayout.usesOverlayScrollers
    }

    private var iconShadowColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.24)
            : Color.black.opacity(0.30)
    }

    /// 选中底色：激活蓝实心/失焦灰，只改内容层，不叠第二层玻璃；高亮只包住行本体。
    @ViewBuilder
    private var selectionBackground: some View {
        Group {
            if isActiveSelection {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(activeSelectionColor)
            } else if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(inactiveSelectionColor)
            }
        }
        .padding(.top, listTopPadding)
        .padding(.bottom, listBottomPadding)
        .padding(.leading, ClipboardLayout.rowHorizontalInset)
        .padding(
            .trailing,
            ClipboardLayout.rowSelectionTrailingInset(usesOverlayScrollers: usesOverlayScrollers)
        )
    }

    private var activeSelectionColor: Color {
        Color(.sRGB, red: 84 / 255, green: 140 / 255, blue: 235 / 255)
    }

    private var inactiveSelectionColor: Color {
        Color(.sRGB, white: 0.45).opacity(0.30)
    }

    private var rowTotalHeight: CGFloat {
        ClipboardLayout.rowHeight + listTopPadding + listBottomPadding
    }

    private var copyButtonRect: CGRect {
        ClipboardLayout.rowCopyButtonRect(listTopPadding: listTopPadding)
    }

    var body: some View {
        HStack(spacing: 0) {
            bodyColumn

            trailingColumn
        }
        .frame(height: rowTotalHeight)
        // 高亮走 background：可伸缩形状放进 ZStack 会把行撑大。
        .background(selectionBackground)
        .overlay {
            RowInteractionHost(
                rowID: row.id,
                onSelect: onSelect,
                onActivate: onActivate,
                makeMenu: menuProvider,
                clickTracker: clickTracker
            )
        }
        // 复制命中层在宿主之上，其余事件放行给宿主；编号占位时让整行照常响应。
        .overlay(alignment: .topTrailing) {
            if shortcutNumber == nil {
                RowCopyHitTarget(onCopy: onCopy)
                    .frame(width: copyButtonRect.width, height: copyButtonRect.height)
                    .padding(.top, copyButtonRect.minY)
                    .padding(
                        .trailing,
                        ClipboardLayout.rowCopyButtonTrailingInset(usesOverlayScrollers: usesOverlayScrollers)
                    )
            }
        }
    }

    private var bodyColumn: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: listTopPadding)
            rowContent
            Color.clear.frame(height: listBottomPadding)
        }
    }

    private var titleTooltipDetail: String? {
        guard row.kind == .file || row.kind == .image,
              let path = row.filePath,
              !path.isEmpty else { return nil }
        return path
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            leadingIcon
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                RowTitleText(
                    text: titleText,
                    isActiveSelection: isActiveSelection,
                    detail: titleTooltipDetail
                )

                Text(subtitleText)
                    .font(.system(size: 12.5))
                    // 语义次级色随外观与「增强对比度」取值；写死灰在玻璃上对比度不足。
                    .foregroundStyle(
                        isActiveSelection
                            ? Color.white.opacity(0.85)
                            : Color.secondary
                    )
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: ClipboardLayout.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelect(row.id) }
    }

    private var trailingColumn: some View {
        Group {
            if let shortcutNumber {
                shortcutNumberView(shortcutNumber)
            } else {
                copyButton
            }
        }
        .padding(.top, copyButtonRect.minY)
        .frame(
            width: ClipboardLayout.rowCopyButtonColumnWidth(usesOverlayScrollers: usesOverlayScrollers),
            height: rowTotalHeight,
            alignment: .topLeading
        )
    }

    /// 按住 ⌘ 时把复制图标换成数字，沿用按钮圆底，UI 变化最小。
    private func shortcutNumberView(_ number: Int) -> some View {
        Text(verbatim: "\(number)")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.primary.opacity(0.82))
            .frame(width: ClipboardLayout.rowCopyButtonSize, height: ClipboardLayout.rowCopyButtonSize)
            .background(Circle().fill(actionButtonFill))
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

    private var subtitleText: LocalizedStringKey {
        let time = context.caches.time.copyTime(
            for: row.id,
            lastActivityAt: row.lastActivityAt,
            locale: locale
        )
        return "\(typeLabelKey) · copied at \(time)"
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

    private var copyButton: some View {
        Button(action: onCopy) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.82))
                .frame(
                    width: ClipboardLayout.rowCopyButtonSize,
                    height: ClipboardLayout.rowCopyButtonSize
                )
                .background(Circle().fill(actionButtonFill))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(NoPressFeedbackButtonStyle())
        .accessibilityLabel(Localizer.string("Copy"))
    }

    /// 行尾操作按钮的圆底；复制与编号共用。
    private var actionButtonFill: Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 90 / 255, green: 90 / 255, blue: 90 / 255).opacity(0.65)
            : Color(.sRGB, red: 200 / 255, green: 200 / 255, blue: 200 / 255).opacity(0.65)
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
                systemIcon("link")
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

/// 行内按钮不要按下反馈，避免与整行选中态打架。
private struct NoPressFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
