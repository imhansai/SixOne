//
//  ListRowShell.swift
//  SixOne
//  历史列表与文件组列表共用的行壳：几何、选中底色、复制命中与交互宿主。
//

import AppKit
import SwiftUI

/// 行级无障碍文案：标题后接类型/时间或文件大小，VoiceOver 不再逐个子元素读。
enum RowAccessibility {
    static func label(title: String, detail: String) -> String {
        detail.isEmpty ? title : "\(title), \(detail)"
    }
}

/// 行外观常量：两套列表共用，避免选中底色和图标阴影各自漂移。
enum RowAppearance {
    static let activeSelection = Color(.sRGB, red: 84 / 255, green: 140 / 255, blue: 235 / 255)
    static let inactiveSelection = Color(.sRGB, white: 0.45).opacity(0.30)

    static func iconShadowColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.24)
            : Color.black.opacity(0.30)
    }
}

/// 行容器：首末行留白折进行高，内容只提供图标与标题/副标题。
struct ListRowShell<Leading: View>: View {
    let rowID: UUID
    let isSelected: Bool
    let isListActive: Bool
    let listTopPadding: CGFloat
    let listBottomPadding: CGFloat
    let shortcutNumber: Int?
    let isCopied: Bool
    let title: String
    let titleTooltipDetail: String?
    let accessibilityDetail: String
    let subtitle: AnyView
    let leading: Leading
    let onCopy: () -> Void
    let onSelect: (UUID) -> Void
    let onActivate: (UUID, Bool) -> Void
    let makeMenu: (RowInteractionHost.HostView) -> NSMenu?
    let clickTracker: RowClickTracker?

    @Environment(PanelContext.self) private var context
    @State private var isCopyButtonPressed = false

    init(
        rowID: UUID,
        isSelected: Bool,
        isListActive: Bool,
        listTopPadding: CGFloat,
        listBottomPadding: CGFloat,
        shortcutNumber: Int?,
        isCopied: Bool,
        title: String,
        titleTooltipDetail: String?,
        accessibilityDetail: String,
        subtitle: AnyView,
        onCopy: @escaping () -> Void,
        onSelect: @escaping (UUID) -> Void,
        onActivate: @escaping (UUID, Bool) -> Void,
        makeMenu: @escaping (RowInteractionHost.HostView) -> NSMenu?,
        clickTracker: RowClickTracker?,
        @ViewBuilder leading: () -> Leading
    ) {
        self.rowID = rowID
        self.isSelected = isSelected
        self.isListActive = isListActive
        self.listTopPadding = listTopPadding
        self.listBottomPadding = listBottomPadding
        self.shortcutNumber = shortcutNumber
        self.isCopied = isCopied
        self.title = title
        self.titleTooltipDetail = titleTooltipDetail
        self.accessibilityDetail = accessibilityDetail
        self.subtitle = subtitle
        self.leading = leading()
        self.onCopy = onCopy
        self.onSelect = onSelect
        self.onActivate = onActivate
        self.makeMenu = makeMenu
        self.clickTracker = clickTracker
    }

    private var isActiveSelection: Bool { isSelected && isListActive }
    private var usesOverlayScrollers: Bool { context.scrollerLayout.usesOverlayScrollers }

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
        .background(selectionBackground)
        // 鼠标交互交给共享宿主：抬起选中、双击激活、右键先选中再弹菜单。
        .overlay {
            RowInteractionHost(
                rowID: rowID,
                onSelect: onSelect,
                onActivate: onActivate,
                makeMenu: makeMenu,
                clickTracker: clickTracker
            )
        }
        // 复制命中层在宿主之上；编号占位时让整行响应。
        .overlay(alignment: .topTrailing) {
            if shortcutNumber == nil {
                RowCopyHitTarget(
                    onCopy: onCopy,
                    onPressChanged: { isCopyButtonPressed = $0 }
                )
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

    private var rowContent: some View {
        HStack(spacing: 16) {
            leading
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                RowTitleText(
                    text: title,
                    isActiveSelection: isActiveSelection,
                    detail: titleTooltipDetail
                )

                subtitle
                    .font(.system(size: 12.5))
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
        .accessibilityLabel(RowAccessibility.label(title: title, detail: accessibilityDetail))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelect(rowID) }
    }

    private var trailingColumn: some View {
        Group {
            if let shortcutNumber {
                RowActionButton(
                    content: .number(shortcutNumber),
                    isActiveSelection: isActiveSelection
                )
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

    private var copyButton: some View {
        Button(action: onCopy) {
            RowActionButton(
                content: .copy(isCopied: isCopied),
                isActiveSelection: isActiveSelection,
                isPressed: isCopyButtonPressed
            )
        }
        .buttonStyle(NoPressFeedbackButtonStyle())
        .accessibilityLabel(Localizer.string("Copy"))
    }

    @ViewBuilder
    private var selectionBackground: some View {
        Group {
            if isActiveSelection {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(RowAppearance.activeSelection)
            } else if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(RowAppearance.inactiveSelection)
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
}
