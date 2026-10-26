//
//  PanelWindowFactory.swift
//  SixOne
//  面板窗口搭建：无边框浮窗 + 玻璃层 + SwiftUI 宿主。

import AppKit
import SwiftUI

enum PanelWindowFactory {
    static func makePanel() -> ClipboardPanel {
        let panel = ClipboardPanel(
            contentRect: NSRect(origin: .zero, size: ClipboardLayout.panelSize),
            // 无标题栏的 titled 窗口由系统给圆角（实测 16pt），sheet 背板才能跟随。
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // 隐形标题栏会吃掉头部点击，系统拖拽须关闭，改由 PanelDragHandle 实现。
        panel.isMovable = false
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        return panel
    }

    static func install(rootView: AnyView, into panel: ClipboardPanel) -> NSViewController {
        let hosting = NSHostingController(rootView: rootView)
        // 窗口尺寸固定，禁止宿主按内容拟合，避免首帧闪出小窗口。
        hosting.sizingOptions = []
        // titled 窗口的标题栏安全区（实测 32pt）会下推内容，必须清掉。
        (hosting.view as? NSHostingView<AnyView>)?.safeAreaRegions = []
        let contentSize = ClipboardLayout.panelSize
        hosting.view.frame = NSRect(origin: .zero, size: contentSize)
        hosting.view.autoresizingMask = [.width, .height]

        let glassView = NSGlassEffectView(frame: NSRect(origin: .zero, size: contentSize))
        glassView.style = .regular
        // 与系统窗口圆角一致，否则非激活时背板四角会露方角。
        glassView.cornerRadius = 16
        glassView.clipsToBounds = true
        glassView.contentView = hosting.view
        glassView.autoresizingMask = [.width, .height]
        panel.contentView = glassView

        // 面板启动即创建但尚未显示，先强制布局，避免首次打开才异步渲染而闪现小窗口。
        panel.layoutIfNeeded()
        hosting.view.layoutSubtreeIfNeeded()
        return hosting
    }
}
