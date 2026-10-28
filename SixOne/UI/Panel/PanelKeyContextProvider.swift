//
//  PanelKeyContextProvider.swift
//  SixOne
//  把此刻面板状态查成 `PanelKeyContext`；只查询，判定在 `PanelKeyRouter`。

import AppKit

struct PanelKeyContextProvider {
    let panel: ClipboardPanel
    let searchState: SearchState
    let moreActionsState: MoreActionsState
    let confirmationState: ConfirmationState
    let previewState: PreviewState
    /// 当前选中条目 id（列表只持轻量行，需要整条时按 id 补齐）。
    let selectedItemID: () -> UUID?
    /// 完整可见且可编号的行数。
    let visibleRowCount: () -> Int

    private var previewSurface: PreviewSurfaceProbe {
        PreviewSurfaceProbe(contentView: panel.contentView, firstResponder: panel.firstResponder)
    }

    func context() -> PanelKeyContext {
        var context = PanelKeyContext()
        context.isPanelKeyWindow = panel.isKeyWindow
        context.isIMEComposing = isIMEComposing()

        let surface = previewSurface
        context.isPreviewFindBarVisible = surface.isFindBarVisible
        context.isPreviewTextFocused = surface.isFocusedOnPreviewText
        context.hasPreviewTextSelection = surface.previewTextSelectionLength > 0

        context.isEditing = previewState.isEditing

        let previewItem = previewState.item
        context.previewKind = previewItem?.kind
        context.previewFileCount = previewItem?.fileCount ?? 0
        context.isViewingGroupFile = previewState.groupFileIndex != nil
        let visibleGroupIndices = previewState.visibleGroupFileIndices
        context.canMoveGroupSelectionUp = previewState.canMoveGroupSelection(by: -1, visibleIndices: visibleGroupIndices)
        context.canMoveGroupSelectionDown = previewState.canMoveGroupSelection(by: 1, visibleIndices: visibleGroupIndices)
        context.focusedGroupFileIndex = previewState.focusedGroupFileIndex
        // 用第一响应者现场判定，避免滞后的状态标记让 ⌘F 被过滤框分支误吞。
        context.isGroupFilterFocused = surface.isFocusedOnGroupFilter

        context.isMoreActionsFocused = moreActionsState.isFocused
        context.isModalPresented = Self.isModalPresented(
            confirmation: confirmationState,
            attachedSheet: panel.attachedSheet
        )
        context.isSearchFocused = searchState.isFocused
        context.hasSelection = selectedItemID() != nil
        context.visibleRowCount = visibleRowCount()

        return context
    }

    /// 确认弹窗看状态，其它挂到面板的 sheet 看窗口现场。
    static func isModalPresented(confirmation: ConfirmationState, attachedSheet: NSWindow?) -> Bool {
        confirmation.isPresenting || attachedSheet != nil
    }

    private func isIMEComposing() -> Bool {
        guard let fieldEditor = panel.firstResponder as? NSTextView else { return false }
        return fieldEditor.hasMarkedText()
    }
}
