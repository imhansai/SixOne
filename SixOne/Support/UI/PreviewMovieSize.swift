//
//  PreviewMovieSize.swift
//  SixOne
//  影片预览比例：只读元数据，按画面比例摆放视图以避免黑边。

import AVFoundation
import CoreGraphics
import Foundation

nonisolated enum PreviewMovieSize {
    /// 影片的展示宽高比（已算上旋转）；读不到（没有视频轨）返回 nil。
    static func aspectRatio(of url: URL) async -> CGFloat? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (naturalSize, transform) = try? await track.load(.naturalSize, .preferredTransform)
        else { return nil }

        let size = naturalSize.applying(transform)
        let width = abs(size.width), height = abs(size.height)
        guard width > 0, height > 0 else { return nil }
        return width / height
    }
}
