//
//  PanelCaches.swift
//  SixOne
//  面板缓存集合：装配处建一份，经 `PanelContext` 注入同一份。

import Foundation

final class PanelCaches {
    let query = ClipboardQueryCache()
    let time = ClipboardTimeCache()
    let preview = ClipboardPreviewCache()
    let textStats = ClipboardTextStatsCache()
    let fileGroupThumbnails = FileGroupThumbnailCache()
}
