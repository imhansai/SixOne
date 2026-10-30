//
//  PanelKeyActionExecutor.swift
//  SixOne
//
//  执行 `PanelKeyRouter` 判定出的动作；返回 false 表示事件继续交给 AppKit。
//

import AppKit

final class PanelKeyActionExecutor {
    private let panel: ClipboardPanel
    private let itemActions: PanelItemActions
    private let editingSession: PanelEditingSession
    private let cursor: PanelSelectionCursor
    private let previewState: PreviewState
    private let previewLauncher: PreviewLauncher
    private let pasteFlow: PanelPasteFlow
    private let focusZones: PanelFocusZones
    private let searchState: SearchState
    private let hide: () -> Void
    private let fullItem: (UUID) -> ClipboardItem?

    init(
        panel: ClipboardPanel,
        itemActions: PanelItemActions,
        editingSession: PanelEditingSession,
        cursor: PanelSelectionCursor,
        previewState: PreviewState,
        previewLauncher: PreviewLauncher,
        pasteFlow: PanelPasteFlow,
        focusZones: PanelFocusZones,
        searchState: SearchState,
        hide: @escaping () -> Void,
        fullItem: @escaping (UUID) -> ClipboardItem?
    ) {
        self.panel = panel
        self.itemActions = itemActions
        self.editingSession = editingSession
        self.cursor = cursor
        self.previewState = previewState
        self.previewLauncher = previewLauncher
        self.pasteFlow = pasteFlow
        self.focusZones = focusZones
        self.searchState = searchState
        self.hide = hide
        self.fullItem = fullItem
    }

    /// 执行判定出的动作。返回 false 表示这一步没做成，事件继续交给 AppKit。
    func apply(_ action: PanelKeyAction) -> Bool {
        switch action {
        case .consume:
            break

        case .hidePanel:
            hide()
        case .cycleFocus(let backwards):
            focusZones.cycle(backwards: backwards)

        case .focusSearch:
            focusZones.focusSearch()

        case .escape:
            editingSession.handleEscape()
        case .cancelEditing:
            editingSession.requestCancelEditing()
        case .dismissPreviewFindBar:
            editingSession.closePreviewFindBar()
        case .performPreviewFindCommand(let command):
            guard editingSession.performPreviewFindCommand(command) else { return false }
        case .openPreviewForSelection:
            if let selectedID = cursor.selectedItemID, let item = fullItem(selectedID) {
                previewLauncher.present(item)
            }
        case .closePreview:
            previewState.close()

        case .activateSelectedItem(let asPlainText):
            itemActions.activateSelected(asPlainText: asPlainText)
        case .activateFocusedGroupFile(let index):
            if let item = previewState.item { pasteFlow.paste(item, fileIndex: index) }
        case .pasteVisibleRow(let offset, let asPlainText):
            itemActions.pasteVisibleRow(offset: offset, asPlainText: asPlainText)
        case .pasteVisibleGroupFile(let offset, let asPlainText):
            itemActions.pasteVisibleGroupFile(offset: offset, asPlainText: asPlainText)

        case .stepPreview(let delta):
            cursor.stepPreview(direction: delta)
        case .jumpPreview(let index):
            cursor.jumpPreview(to: index)
        case .jumpPreviewToOldest:
            cursor.jumpPreviewToOldest()
        case .moveGroupSelection(let delta):
            previewState.moveGroupSelection(by: delta, visibleIndices: previewState.visibleGroupFileIndices)
        case .jumpGroupSelection(let toFirst):
            previewState.jumpGroupSelection(toFirst: toFirst, visibleIndices: previewState.visibleGroupFileIndices)
        case .stepGroupFile(let delta):
            previewState.stepGroupFile(delta: delta, visibleIndices: previewState.visibleGroupFileIndices)
        case .jumpGroupFile(let toFirst):
            previewState.jumpGroupFile(toFirst: toFirst, visibleIndices: previewState.visibleGroupFileIndices)
        case .showGroupFile(let index):
            previewState.showGroupFile(index)
        case .showGroupOverview:
            previewState.showGroupOverview()
        case .focusGroupFilter:
            searchState.resignFocus()
            previewState.focusGroupFilter()
        case .focusGroupList:
            previewState.moveFromGroupFilterToList()
            panel.makeFirstResponder(panel.contentView)
        }
        return true
    }
}
