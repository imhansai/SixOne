//
//  FilePreviewContent.swift
//  SixOne
//
//  单个文件的内容渲染：按 FilePreviewKind 选择渲染器；预取结果与 URL 绑定，切换时自动重置。
//

import SwiftUI

struct FilePreviewContent: View {
    let url: URL

    @State private var imageState: ImageLoadState = .idle
    /// 影片展示宽高比，供 Quick Look 居中并收住黑底。
    @State private var videoAspect: CGFloat?

    var body: some View {
        content.task(id: url) {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch FilePreviewKind.of(url) {
        case .image:
            imageContent
        case .html:
            HTMLPreviewContainer(url: url)
        case .pdf:
            PDFPreview(url: url)
        case .text:
            TextFilePreview(url: url)
        case .quickLook:
            QuickLookPreview(url: url, videoAspect: videoAspect)
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        switch imageState {
        case .idle:
            ProgressView()
                .controlSize(.small)
        case .loaded(let tier):
            InteractiveImagePreview(identity: url.path, tier: tier) { maxPixelSize in
                await Self.decodeImage(at: url, maxPixelSize: maxPixelSize)
            }
        case .failed:
            PreviewUnavailable()
        }
    }

    /// 预取图片解码或影片比例；每处 await 后都要丢弃迟到的结果。
    private func load() async {
        videoAspect = nil
        if FilePreviewKind.isMovie(url) {
            let aspect = await PreviewMovieSize.aspectRatio(of: url)
            guard !Task.isCancelled else { return }
            videoAspect = aspect
            return
        }
        guard case .image = FilePreviewKind.of(url) else { return }
        imageState = .idle
        let tier = await Self.decodeImage(at: url, maxPixelSize: ClipboardLayout.previewImageBasePixelSize)
        guard !Task.isCancelled else { return }
        imageState = tier.map(ImageLoadState.loaded) ?? .failed
    }

    private static func decodeImage(at url: URL, maxPixelSize: Int) async -> PreviewImageDecoder.Tier? {
        await PreviewImageDecoder.decode(contentsOf: url, maxPixelSize: maxPixelSize)
    }

    private enum ImageLoadState {
        case idle
        case loaded(PreviewImageDecoder.Tier)
        case failed
    }
}
