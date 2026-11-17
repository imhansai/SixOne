//
//  FileCapabilities.swift
//  SixOne
//
//  菜单命令的文件能力结论与探测输入：纯值，可跨线程。
//

import Foundation

nonisolated struct FileCapabilities: Sendable, Equatable {
    var canOpen: Bool
    var canReveal: Bool

    static let none = FileCapabilities(canOpen: false, canReveal: false)
}

/// 从轻量条目拷出的探测输入；后台不碰库。
nonisolated struct FileCapabilityRequest: Sendable {
    let itemID: UUID
    let recencyID: UUID
    let kind: ClipboardItemKind
    let paths: [String]
    let bookmark: Data?
    let bookmarks: Data?
    let hasInlineImage: Bool
    let hasText: Bool
    let isOpenableLink: Bool
}

extension FileCapabilityRequest {
    /// 轻量条目 → 探测输入；菜单缓存与测试共用。
    @MainActor
    init(item: ClipboardItem, manager: ClipboardManager) {
        self.init(
            itemID: item.id,
            recencyID: item.recencyID,
            kind: item.kind,
            paths: item.allFilePaths,
            bookmark: item.securityScopeBookmark,
            bookmarks: item.securityScopeBookmarks,
            hasInlineImage: item.kind == .image && manager.hasInlineImage(id: item.id),
            hasText: item.kind == .text && manager.hasText(id: item.id),
            // 链接正文很短，按需补取；文本条目不读全文。
            isOpenableLink: item.linkURL != nil
        )
    }
}

nonisolated struct FileCapabilityResolution: Sendable {
    let capabilities: FileCapabilities
    /// 过期 bookmark，交回主线程回写。
    let refreshedBookmarks: [RefreshedBookmark]
}
