//
//  PanelItemActions.swift
//  SixOne
//
//  条目级动作：复制、粘贴、打开、分享、删除、清空与快速粘贴。
//

import AppKit

final class PanelItemActions {
    private let manager: ClipboardManager
    private let store: HistoryListStore
    private let panel: ClipboardPanel
    private let previewState: PreviewState
    private let navigationState: NavigationState
    private let copyState: CopyState
    private let noticeState: NoticeState
    private let confirmationState: ConfirmationState
    private let cursor: PanelSelectionCursor
    private let previewLauncher: PreviewLauncher
    private let pasteFlow: PanelPasteFlow
    private let sharing: PanelSharing
    /// 交给外部应用后收起面板，不抢回原应用焦点。
    private let handOff: () -> Void

    init(
        manager: ClipboardManager,
        store: HistoryListStore,
        panel: ClipboardPanel,
        previewState: PreviewState,
        navigationState: NavigationState,
        copyState: CopyState,
        noticeState: NoticeState,
        confirmationState: ConfirmationState,
        cursor: PanelSelectionCursor,
        previewLauncher: PreviewLauncher,
        pasteFlow: PanelPasteFlow,
        sharing: PanelSharing,
        handOff: @escaping () -> Void
    ) {
        self.manager = manager
        self.store = store
        self.panel = panel
        self.previewState = previewState
        self.navigationState = navigationState
        self.copyState = copyState
        self.noticeState = noticeState
        self.confirmationState = confirmationState
        self.cursor = cursor
        self.previewLauncher = previewLauncher
        self.pasteFlow = pasteFlow
        self.sharing = sharing
        self.handOff = handOff
    }

    // MARK: - 粘贴 / 打开

    func activate(id: UUID, asPlainText: Bool) {
        guard let item = fullItem(id: id) else { return }
        // 无纯文本形态的条目回落普通粘贴。
        pasteFlow.paste(item, asPlainText: asPlainText && item.kind.hasPlainText)
    }

    func pasteAsPlainText(id: UUID) {
        guard let item = fullItem(id: id) else { return }
        pasteFlow.paste(item, asPlainText: true)
    }

    func activateSelected(asPlainText: Bool) {
        guard let id = cursor.selectedItemID, let item = fullItem(id: id) else { return }
        pasteFlow.paste(item, asPlainText: asPlainText && item.kind.hasPlainText)
    }

    func requestOpen(id: UUID) {
        guard let item = fullItem(id: id) else { return }
        openExternally(item)
    }

    func openCurrentItem() {
        guard let item = currentItem, let full = fullItem(id: item.id) else { return }
        openExternally(full)
    }

    func revealCurrentItem() {
        guard let item = currentItem else { return }
        if item.kind == .file, item.fileCount > 1 {
            let urls = manager.resolvedFileURLs(for: item).compactMap { $0 }
            guard !urls.isEmpty else {
                noticeState.showMissingFile(item.displayTitle)
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        } else if let url = manager.fileURL(for: item, allowTemporaryCopy: false) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            noticeState.showMissingFile(item.displayTitle)
            return
        }
        handOff()
    }

    private func openExternally(_ item: ClipboardItem) {
        // 文件组逐个用各自默认应用打开；NSWorkspace 没有批量按默认应用打开的 API。
        if item.kind == .file, item.fileCount > 1 {
            let urls = manager.resolvedFileURLs(for: item).compactMap { $0 }
            guard !urls.isEmpty else {
                noticeState.showMissingFile(item.displayTitle)
                return
            }
            for url in urls { NSWorkspace.shared.open(url) }
            handOff()
            return
        }

        guard let url = manager.fileURL(for: item) else {
            // 文件条目是不存在了，图片条目是取不到内容。
            if item.kind == .file {
                noticeState.showMissingFile(item.displayTitle)
            } else {
                noticeState.showInaccessibleFile(item.displayTitle)
            }
            return
        }
        NSWorkspace.shared.open(url)
        handOff()
    }

    // MARK: - 复制 / 粘贴当前条目

    /// 命令作用条目：预览打开时优先预览项，否则按列表选中查库。
    var currentItem: ClipboardItem? {
        if let preview = previewState.item { return preview }
        guard let id = cursor.selectedItemID else { return nil }
        return manager.fetchLightItem(id: id)
    }

    func copySelectedItem() {
        guard let item = currentItem else { return }
        if item.kind == .file, item.fileCount > 1,
           let index = previewState.focusedGroupFileIndex {
            copyGroupFile(at: index, of: item)
            return
        }
        manager.copy(id: item.id)
        copyState.itemID = item.id
    }

    func pasteSelectedItem() {
        guard let item = currentItem else { return }
        if item.kind == .file, item.fileCount > 1,
           let index = previewState.focusedGroupFileIndex {
            pasteFlow.paste(item, fileIndex: index)
            return
        }
        guard let full = fullItem(id: item.id) else { return }
        pasteFlow.paste(full)
    }

    func copyAsPlainTextForCurrentItem() {
        guard let item = currentItem, item.kind.hasPlainText else { return }
        manager.copyAsPlainText(id: item.id)
        copyState.itemID = item.id
    }

    /// 指定条目复制；复制反馈由调用方负责。
    func copyItem(id: UUID) {
        manager.copy(id: id)
    }

    func copyItemAsPlainText(id: UUID) {
        manager.copyAsPlainText(id: id)
    }

    /// 复制不属于历史条目的文字，不触达历史。
    func copyText(_ text: String) {
        manager.copyPlainText(text)
    }

    func saveEditedText(id: UUID, text: String, richText: Data?) {
        manager.updateEditedText(id: id, text: text, richText: richText)
    }

    func pasteAsPlainTextForCurrentItem() {
        guard let item = currentItem, item.kind.hasPlainText,
              let full = fullItem(id: item.id) else { return }
        pasteFlow.paste(full, asPlainText: true)
    }

    func previewCurrentItem() {
        if previewState.item != nil {
            previewState.close()
            return
        }
        guard let item = currentItem, let full = fullItem(id: item.id) else { return }
        previewLauncher.present(full)
    }

    func deleteSelectedItem() {
        guard let item = currentItem else { return }
        requestDelete(id: item.id)
    }

    // MARK: - 删除 / 清空

    func requestDelete(id: UUID) {
        guard manager.fetchLightItem(id: id) != nil else { return }
        confirmationState.pendingDeletionID = id
        ConfirmationAlert.present(
            on: panel,
            title: Localizer.string("Delete Item?"),
            message: Localizer.string("This cannot be undone."),
            actionTitle: Localizer.string("Delete"),
            onAction: { [weak self] in self?.confirmDelete(id: id) },
            onCancel: { [weak self] in self?.confirmationState.pendingDeletionID = nil }
        )
    }

    private func confirmDelete(id: UUID) {
        confirmationState.pendingDeletionID = nil
        guard let item = manager.fetchLightItem(id: id) else { return }
        if previewState.item?.id == item.id {
            previewState.close()
        }
        manager.delete(id: item.id)
        if cursor.selectedItemID == item.id {
            cursor.selectedItemID = nil
            navigationState.isSelectionActive = false
        }
    }

    func requestClearHistory() {
        guard !store.rows.isEmpty else { return }
        confirmationState.isClearingHistory = true
        ConfirmationAlert.present(
            on: panel,
            title: Localizer.string("Clear History?"),
            message: Localizer.string("This deletes all clipboard history. It cannot be undone."),
            actionTitle: Localizer.string("Clear History"),
            onAction: { [weak self] in
                self?.manager.clearAll()
                self?.confirmationState.isClearingHistory = false
            },
            onCancel: { [weak self] in self?.confirmationState.isClearingHistory = false }
        )
    }

    // MARK: - 分享

    func requestShare(id: UUID, anchorView: NSView) {
        sharing.shareRowItem(id: id, anchorView: anchorView)
    }

    func requestGroupFileShare(at index: Int, anchorView: NSView) {
        guard let item = previewState.item, item.kind == .file, item.fileCount > 1 else { return }
        sharing.sharePreviewedFile(at: index, of: item, anchorView: anchorView)
    }

    func requestShareGroup(anchorView: NSView?) {
        guard let item = previewState.item, item.kind == .file, item.fileCount > 1,
              let anchor = anchorView ?? panel.contentView else { return }
        sharing.sharePreviewedGroup(item, anchorView: anchor)
    }

    func shareCurrentItem() {
        guard let item = currentItem, let anchor = panel.contentView else { return }
        if previewState.item?.id == item.id, item.kind == .file, item.fileCount > 1 {
            if let index = previewState.focusedGroupFileIndex {
                sharing.sharePreviewedFile(at: index, of: item, anchorView: anchor)
            } else {
                sharing.sharePreviewedGroup(item, anchorView: anchor)
            }
            return
        }
        sharing.shareRowItem(id: item.id, anchorView: anchor)
    }

    // MARK: - 文件组

    func invokeGroupFileCommand(_ command: GroupFileCommand, index: Int) {
        guard let item = previewState.item, item.kind == .file, item.fileCount > 1 else { return }
        switch command {
        case .paste:
            pasteFlow.paste(item, fileIndex: index)
        case .copy:
            copyGroupFile(at: index, of: item)
        case .open, .reveal:
            break
        }
    }

    private func copyGroupFile(at index: Int, of item: ClipboardItem) {
        if manager.copy(item, fileAt: index) {
            copyState.itemID = item.id
            previewState.markGroupFileCopied(at: index)
            return
        }
        let path = item.allFilePaths.indices.contains(index) ? item.allFilePaths[index] : ""
        noticeState.showMissingFile(URL(fileURLWithPath: path).lastPathComponent)
    }

    // MARK: - 快速粘贴

    /// ⌘+数字：先选中当前完整可见区的第 offset 行再粘贴；失败时面板保留并沿用现有提示。
    func pasteVisibleRow(offset: Int, asPlainText: Bool) {
        guard let range = navigationState.fullyVisibleRange else { return }
        let index = range.lowerBound + offset
        guard range.contains(index), store.rows.indices.contains(index) else { return }
        let id = store.rows[index].id
        guard let full = fullItem(id: id) else { return }
        if asPlainText, !full.kind.hasPlainText { return }
        navigationState.selectedItemID = id
        pasteFlow.paste(full, asPlainText: asPlainText)
    }

    /// ⌘+数字：粘贴组内可见区的第 offset 个文件。
    func pasteVisibleGroupFile(offset: Int, asPlainText: Bool) {
        guard previewState.isGroupOverview, let item = previewState.item else { return }
        // 文件没有纯文本形态，⇧ 变体不动作（与外层列表一致）。
        guard !asPlainText else { return }
        guard let range = previewState.groupVisibleRowRange else { return }
        let position = range.lowerBound + offset
        guard range.contains(position),
              let index = previewState.groupFileIndex(atVisiblePosition: position) else { return }
        previewState.selectGroupFile(index)
        pasteFlow.paste(item, fileIndex: index)
    }

    // MARK: - 辅助

    private func fullItem(id: UUID) -> ClipboardItem? {
        manager.fetchFullItem(id: id)
    }
}
