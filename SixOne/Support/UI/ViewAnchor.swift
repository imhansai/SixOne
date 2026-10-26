//
//  ViewAnchor.swift
//  SixOne
//  把 SwiftUI 控件位置暴露成 AppKit 视图，供需要 NSView 锚点的系统面板使用。

import AppKit
import SwiftUI

/// 弱持有锚点视图，避免两侧互相持有。
@MainActor
final class ViewAnchorBox {
    weak var view: NSView?
}

struct ViewAnchor: NSViewRepresentable {
    let box: ViewAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = AnchorView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }

    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
