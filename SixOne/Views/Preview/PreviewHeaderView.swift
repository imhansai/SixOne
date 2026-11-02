//
//  PreviewHeaderView.swift
//  SixOne
//  预览顶栏：普通条目的标题/副标题/动作，以及文件组总览的筛选与操作。
//

import SwiftUI

struct PreviewHeaderView: View {
    let item: ClipboardItem
    let subtitle: String?
    let fileNameTitle: String?
    let linkOrigin: String?
    let fileURL: URL?
    let linkURL: URL?
    let isGroupFileView: Bool

    @Environment(PanelContext.self) private var context

    private var previewState: PreviewState { context.previewState }
    private var editingActions: EditingActionHandling? { context.editingActions }
    private var shellActions: ShellActionHandling? { context.shellActions }

    var body: some View {
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
                                context.copyText(text)
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
                    // 显示格式开关仅只读态出现，编辑态隐去但占位；超上限只渲染纯文本，开关无意义。
                    if item.kind == .text,
                       item.attributedTextData != nil,
                       !item.exceedsTextPreviewLimit {
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

    /// 只读态关闭预览；编辑态取消编辑；组内单文件态退回组列表。
    private var closePreviewButton: some View {
        PreviewHeaderActionButton(systemImage: "xmark", help: closeButtonHelp) {
            if previewState.isEditing {
                // 有改动时由面板先弹确认，不能直接丢弃。
                if let editingActions {
                    editingActions.panelDidRequestCancelEditing()
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

    private var editToggleButton: some View {
        // 超上限的正文只渲染了开头；编辑会把这截写回条目。
        let isDisabled = !previewState.isEditing && item.exceedsTextPreviewLimit
        return PreviewHeaderActionButton(
            systemImage: previewState.isEditing ? "checkmark" : "pencil",
            help: isDisabled
                ? Localizer.string("Content too large to edit")
                : previewState.isEditing
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
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
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

    @ViewBuilder
    private var openWithMenu: some View {
        if let fileURL {
            PreviewOpenWithMenu(
                fileURL: fileURL,
                onHandOff: { shellActions?.panelDidHandOffToExternalApp() }
            )
            // 组内切换文件时重建，重新枚举打开方式。
            .id(fileURL)
        }
    }

    @ViewBuilder
    private var openLinkButton: some View {
        if let linkURL {
            PreviewLinkOpenButton(
                url: linkURL,
                onHandOff: { shellActions?.panelDidHandOffToExternalApp() },
                onError: { message in context.noticeState.message = message }
            )
        }
    }
}

struct PreviewGroupHeaderView: View {
    let item: ClipboardItem
    let groupMeta: PreviewGroupMeta?
    let shareAnchor: ViewAnchorBox
    let onRevealGroup: () -> Void

    @Environment(PanelContext.self) private var context

    private var previewState: PreviewState { context.previewState }
    private var groupActionHandler: GroupActionHandling? { context.groupActions }
    private var shellActions: ShellActionHandling? { context.shellActions }

    var body: some View {
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
                groupActionHandler?.panelDidRequestShareGroup(anchorView: shareAnchor.view)
            }
            .background(ViewAnchor(box: shareAnchor))

            PreviewHeaderActionButton(
                systemImage: "folder",
                help: Localizer.string("Reveal in Finder")
            ) {
                onRevealGroup()
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
                if wasEmpty { shellActions?.panelDidRequestFocusContent() }
            },
            onMoveDown: {
                previewState.moveFromGroupFilterToList()
                shellActions?.panelDidRequestFocusContent()
            },
            onTab: { _ in
                previewState.moveFromGroupFilterToList()
                shellActions?.panelDidRequestFocusContent()
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
        PreviewSubtitle.groupCount(count: item.fileCount, meta: groupMeta)
    }

    private var groupSizeText: String? {
        PreviewSubtitle.groupSize(meta: groupMeta)
    }
}
