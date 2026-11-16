//
//  GroupPreviewCoordinator.swift
//  SixOne
//  文件组预览策略：条目映射、可见集、焦点与命令分发。
//

import AppKit

@MainActor
struct GroupPreviewCoordinator {
    let item: ClipboardItem
    let groupURLs: [URL?]
    let previewState: PreviewState
    let groupActions: GroupActionHandling?
    let shellActions: ShellActionHandling?
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var revealURL: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }

    var entries: [GroupFileEntry] {
        item.allFilePaths.enumerated().map { index, path in
            GroupFileEntry(
                index: index,
                path: path,
                url: url(at: index)
            )
        }
    }

    var visibleEntries: [GroupFileEntry] {
        let entries = entries
        return previewState.visibleGroupFileIndices.compactMap { index in
            entries.indices.contains(index) ? entries[index] : nil
        }
    }

    var viewingIndex: Int? {
        guard let index = previewState.groupFileIndex,
              groupURLs.indices.contains(index) else { return nil }
        return index
    }

    private func url(at index: Int) -> URL? {
        groupURLs.indices.contains(index) ? groupURLs[index] : nil
    }

    func select(_ index: Int?) {
        previewState.selectGroupFile(index)
        shellActions?.panelDidRequestFocusContent()
    }

    func preview(_ index: Int) {
        previewState.showGroupFile(index)
    }

    func visibleRangeDidChange(_ range: ClosedRange<Int>) {
        guard previewState.item?.id == item.id else { return }
        previewState.groupVisibleRowRange = range
    }

    func share(_ index: Int, anchorView: NSView) {
        groupActions?.panelDidRequestGroupFileShare(at: index, anchorView: anchorView)
    }

    func handle(_ command: GroupFileCommand, index: Int) {
        switch command {
        case .open:
            guard let url = url(at: index) else { return }
            openURL(url)
            shellActions?.panelDidHandOffToExternalApp()
        case .reveal:
            guard let url = url(at: index) else { return }
            revealURL(url)
            shellActions?.panelDidHandOffToExternalApp()
        case .paste, .copy:
            groupActions?.panelDidInvokeGroupFileCommand(command, index: index)
        }
    }
}
