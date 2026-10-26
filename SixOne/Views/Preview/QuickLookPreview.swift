//
//  QuickLookPreview.swift
//  SixOne

import AppKit
import QuickLookUI
import SwiftUI

/// Quick Look 预览；影片按画面比例居中，使系统 letterbox 黑底不露出。
struct QuickLookPreview: NSViewRepresentable {
    let url: URL
    var videoAspect: CGFloat? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> QuickLookHostView {
        let view = QuickLookHostView()
        view.show(url: url, videoAspect: videoAspect)
        return view
    }

    func updateNSView(_ view: QuickLookHostView, context: Context) {
        guard !context.coordinator.isDismantled else { return }
        view.show(url: url, videoAspect: videoAspect)
    }

    static func dismantleNSView(_ view: QuickLookHostView, coordinator: Coordinator) {
        coordinator.isDismantled = true
        view.closePreview()
    }

    final class Coordinator {
        var isDismantled = false
    }
}

final class QuickLookHostView: NSView {
    private let previewView = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
    private var currentURL: URL?
    private var videoAspect: CGFloat?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        // 面板隐藏时窗口不会真正关闭；不自动 close，改由 dismantleNSView 显式释放。
        previewView.shouldCloseWithWindow = false
        addSubview(previewView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 切换预览项或比例；previewItem 被摘掉后需重新装载。
    func show(url: URL, videoAspect: CGFloat?) {
        if currentURL != url || previewView.previewItem == nil {
            currentURL = url
            previewView.previewItem = url as NSURL
        }
        if self.videoAspect != videoAspect {
            self.videoAspect = videoAspect
            needsLayout = true
        }
    }

    func closePreview() {
        // 先清空 previewItem 再 close，避免远程视图服务留下断连日志。
        previewView.previewItem = nil
        previewView.close()
    }

    override func layout() {
        super.layout()
        previewView.frame = fittedFrame()
    }

    private func fittedFrame() -> NSRect {
        guard let aspect = videoAspect, aspect > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        var height = bounds.width / aspect
        if height > bounds.height {
            height = bounds.height
        }
        let width = height * aspect
        return NSRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
    }
}
