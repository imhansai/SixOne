//
//  PanelCommandAvailability.swift
//  SixOne
//  菜单命令的可用态；菜单与键盘 fallback 共用同一份判定。

import Foundation

enum PanelMenuCommand: CaseIterable {
    case copy
    case paste
    case copyAsPlainText
    case pasteAsPlainText
    case delete
    case preview
    case saveEditing
    case open
    case reveal
    case share
    case clearHistory
    case focusSearch
}

struct PanelCommandAvailability: Equatable {
    /// 面板是不是当前 key 窗口；设置窗口为 key 时面板命令不该可用。
    var isPanelKeyWindow = true
    /// 正在文本编辑；此时命令交给文本响应链，面板不接。
    var isTextEditing = false
    var hasSelection = false
    var selectionKind: ClipboardItemKind?
    var isPreviewing = false
    var focusedGroupFileIndex: Int?
    /// 能否交给外部应用打开 / 分享（文件可达、图片有位图、链接有 scheme）。
    var canOpenExternally = false
    /// 有没有真实本地文件可供「在访达中显示」；内联图片可打开但无源文件。
    var hasRevealableFile = false
    var hasHistory = false
    /// 预览正文是否处于编辑态；与 `isTextEditing` 不同，后者也覆盖搜索框与查找栏。
    var isEditing = false

    func isEnabled(_ command: PanelMenuCommand) -> Bool {
        guard isPanelKeyWindow else { return false }

        // 存储是编辑态自己的命令：此时 isTextEditing 必为 true，须先于让路判定。
        if command == .saveEditing { return isEditing }

        if isTextEditing { return false }

        switch command {
        case .copy, .paste:
            return hasSelection || focusedGroupFileIndex != nil
        case .copyAsPlainText, .pasteAsPlainText:
            // 文件组里聚焦的是文件，没有「整组纯文本」。
            return focusedGroupFileIndex == nil && (selectionKind?.hasPlainText ?? false)
        case .delete:
            return hasSelection
        case .preview:
            return isPreviewing || hasSelection
        case .saveEditing:
            return isEditing
        case .open:
            return hasSelection && canOpenExternally
        case .reveal:
            return hasSelection
                && hasRevealableFile
                && (selectionKind == .file || selectionKind == .image)
        case .share:
            return hasSelection
                && canOpenExternally
                && (selectionKind == .file || selectionKind == .image || selectionKind == .link)
        case .clearHistory:
            return hasHistory
        case .focusSearch:
            return !isPreviewing
        }
    }
}
