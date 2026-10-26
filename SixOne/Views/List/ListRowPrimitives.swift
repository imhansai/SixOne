//
//  ListRowPrimitives.swift
//  SixOne
//
//  历史列表与文件组列表共用的 AppKit 行容器积木：滚动视图、裁剪视图、行视图与单元格宿主。
//

import AppKit
import SwiftUI

final class ListRowCellView: NSTableCellView {
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        host.frame = bounds
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent(_ content: AnyView) {
        host.rootView = content
    }

    override func layout() {
        super.layout()
        if host.frame != bounds {
            host.frame = bounds
        }
    }
}

final class ListPlainRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}
}

/// 程序化滚动关闭动画，让选中、视口和滚动条同帧落定。
final class ListClipView: NSClipView {
    private var isScrollAnimationEnabled = true

    func scrollSynchronously(to newOrigin: NSPoint) {
        isScrollAnimationEnabled = false
        defer { isScrollAnimationEnabled = true }
        scroll(to: newOrigin)
    }

    override func scroll(to newOrigin: NSPoint) {
        guard !isScrollAnimationEnabled else {
            super.scroll(to: newOrigin)
            return
        }
        setBoundsOrigin(newOrigin)
    }
}

/// 列表滚动视图；`isScrollBlocked` 时丢弃滚轮事件（sheet 挡不住父窗口滚轮）。
final class ListScrollView: NSScrollView {
    var isScrollBlocked = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let clipView = ListClipView(frame: bounds)
        clipView.autoresizingMask = [.width, .height]
        contentView = clipView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func scrollWheel(with event: NSEvent) {
        guard !isScrollBlocked else { return }
        super.scrollWheel(with: event)
    }

    @discardableResult
    func scrollViewport(toY targetY: CGFloat) -> Bool {
        let clip = contentView
        let origin = NSPoint(x: clip.bounds.origin.x, y: targetY)
        guard clip.bounds.origin != origin else { return false }
        if let listClip = clip as? ListClipView {
            listClip.scrollSynchronously(to: origin)
        } else {
            clip.scroll(to: origin)
        }
        reflectScrolledClipView(clip)
        flashScrollers()
        return true
    }
}
