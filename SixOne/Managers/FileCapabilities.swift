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

nonisolated struct FileCapabilityResolution: Sendable {
    let capabilities: FileCapabilities
    /// 过期 bookmark，交回主线程回写。
    let refreshedBookmarks: [RefreshedBookmark]
}
