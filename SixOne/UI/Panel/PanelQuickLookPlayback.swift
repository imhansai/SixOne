//
//  PanelQuickLookPlayback.swift
//  SixOne
//
//  Quick Look 影片的播放挂起与恢复：影片挂在视图树上，收起时只有摘掉 previewItem 才会停。
//

import AppKit
import QuickLookUI

final class PanelQuickLookPlayback {
    private let panel: ClipboardPanel
    private var suspendedItemURL: URL?

    init(panel: ClipboardPanel) {
        self.panel = panel
    }

    /// 影片播放跑在 QuickLookUIService，只有摘掉 previewItem 才会停（约 2s 尾音）。
    func suspend() {
        guard let view = previewSurface.quickLookView(),
              let url = view.previewItem as? URL,
              FilePreviewKind.isMovie(url) else { return }
        suspendedItemURL = url
        view.previewItem = nil
    }

    func restoreIfNeeded(hasPreview: Bool) {
        let suspended = suspendedItemURL
        suspendedItemURL = nil
        guard hasPreview, let url = suspended else { return }
        previewSurface.quickLookView()?.previewItem = url as NSURL
    }

    private var previewSurface: PreviewSurfaceProbe {
        PreviewSurfaceProbe(contentView: panel.contentView, firstResponder: panel.firstResponder)
    }
}
