//
//  PanelPositioner.swift
//  SixOne

import AppKit

/// 面板定位：把唤出锚点换算成窗口原点，再钳制进屏幕可见区。
enum PanelPositioner {
    struct Screen {
        let frame: CGRect
        let visibleFrame: CGRect

        init(frame: CGRect, visibleFrame: CGRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }

        init(_ screen: NSScreen) {
            self.init(frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }

    private static let statusItemGap: CGFloat = 6
    private static let fallbackTopInset: CGFloat = 32

    /// 计算面板原点（屏幕坐标，原点在左下）；状态项位置缺失时回落屏幕顶部居中。
    static func origin(
        for anchor: PanelAnchor,
        panelSize: CGSize,
        statusItemRect: CGRect?,
        mouseLocation: CGPoint,
        screens: [Screen],
        mainScreen: Screen?
    ) -> CGPoint {
        let reference: CGPoint
        var origin: CGPoint

        switch anchor {
        case .statusItem:
            if let rect = statusItemRect {
                reference = CGPoint(x: rect.midX, y: rect.midY)
                origin = CGPoint(
                    x: rect.midX - panelSize.width / 2,
                    y: rect.minY - panelSize.height - statusItemGap
                )
            } else if let screen = mainScreen ?? screens.first {
                reference = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
                origin = CGPoint(
                    x: screen.frame.midX - panelSize.width / 2,
                    y: screen.frame.maxY - panelSize.height - fallbackTopInset
                )
            } else {
                reference = .zero
                origin = .zero
            }
        case .mouse:
            // 面板左上角对准指针；窗口原点在左下，y 按面板高度换算。
            reference = mouseLocation
            origin = CGPoint(x: mouseLocation.x, y: mouseLocation.y - panelSize.height)
        }

        // 钳制进屏幕可见区；放不下时贴左 / 贴顶，避免区间翻转。
        if let screen = screen(containing: reference, screens: screens, mainScreen: mainScreen) {
            let frame = screen.visibleFrame
            origin.x = frame.width >= panelSize.width
                ? min(max(origin.x, frame.minX), frame.maxX - panelSize.width)
                : frame.minX
            origin.y = frame.height >= panelSize.height
                ? min(max(origin.y, frame.minY), frame.maxY - panelSize.height)
                : frame.maxY - panelSize.height
        }
        return origin
    }

    /// 包含指定点的屏幕；无匹配时回落主屏，再回落第一块。
    private static func screen(containing point: CGPoint, screens: [Screen], mainScreen: Screen?) -> Screen? {
        screens.first { $0.frame.contains(point) } ?? mainScreen ?? screens.first
    }
}
