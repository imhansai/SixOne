//
//  PanelCaches.swift
//  SixOne
//  面板缓存集合：装配处建一份，经 `PanelContext` 注入同一份。

import AppKit

final class PanelCaches {
    let query = ClipboardQueryCache()
    let time = ClipboardTimeCache()
    let preview = ClipboardPreviewCache()
    let textStats = ClipboardTextStatsCache()
    let fileGroupThumbnails = FileGroupThumbnailCache()

    func fileIcon(for path: String) -> NSImage? {
        preview.image(for: "file-\(path)") {
            NSWorkspace.shared.icon(forFile: path)
        }
    }

    func appIcon(for bundleID: String) -> NSImage? {
        guard let url = query.appURL(for: bundleID) else { return nil }
        return preview.image(for: "app-\(bundleID)") {
            NSWorkspace.shared.icon(forFile: url.path)
        }
    }
}
