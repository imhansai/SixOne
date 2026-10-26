//
//  PanelPositionerTests.swift
//  SixOneTests

import CoreGraphics
import Testing
@testable import SixOne

@Suite("面板定位")
struct PanelPositionerTests {
    private let panelSize = CGSize(width: 640, height: 545)
    private var mainScreen: PanelPositioner.Screen {
        PanelPositioner.Screen(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1175),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1175)
        )
    }

    @Test("状态项唤出：面板顶边贴在图标下方并水平居中")
    func statusItemIsCenteredBelowIcon() {
        let origin = place(
            anchor: .statusItem,
            statusItemRect: CGRect(x: 1000, y: 1100, width: 24, height: 24)
        )

        #expect(origin == CGPoint(x: 692, y: 549))
    }

    @Test("贴到可见区边缘时被钳制回来")
    func clampsToVisibleFrame() {
        let right = place(
            anchor: .statusItem,
            statusItemRect: CGRect(x: 1900, y: 1100, width: 24, height: 24)
        )
        #expect(right.x == CGFloat(1920 - 640))

        let bottom = place(
            anchor: .statusItem,
            statusItemRect: CGRect(x: 1000, y: 30, width: 24, height: 24)
        )
        #expect(bottom.y == 0)
    }

    @Test("多屏：用包含锚点的那块屏幕钳制，而不是主屏")
    func clampsToTheScreenContainingTheAnchor() {
        let secondary = PanelPositioner.Screen(
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        )
        let origin = place(
            anchor: .statusItem,
            statusItemRect: CGRect(x: 1930, y: 1050, width: 24, height: 24),
            screens: [mainScreen, secondary]
        )

        #expect(origin.x == CGFloat(1920))
    }

    @Test("取不到状态项位置时回落到屏幕顶部居中")
    func fallsBackToScreenTop() {
        let origin = place(anchor: .statusItem, statusItemRect: nil)

        #expect(origin == CGPoint(x: 960 - 320, y: 1175 - 545 - 32))
    }

    @Test("一块屏幕都没有时不做任何计算")
    func noScreens() {
        let origin = PanelPositioner.origin(
            for: .statusItem,
            panelSize: panelSize,
            statusItemRect: nil,
            mouseLocation: .zero,
            screens: [],
            mainScreen: nil
        )

        #expect(origin == .zero)
    }

    @Test("鼠标唤出：面板左上角对准指针")
    func mouseAnchored() {
        let origin = place(anchor: .mouse, mouseLocation: CGPoint(x: 500, y: 900))

        #expect(origin == CGPoint(x: 500, y: 900 - 545))
    }

    @Test("鼠标唤出也会被钳制")
    func mouseAnchoredIsClamped() {
        let origin = place(anchor: .mouse, mouseLocation: CGPoint(x: 500, y: 100))

        #expect(origin.y == 0)
    }

    @Test("面板大于可见区时贴左贴顶")
    func oversizedPanelPinsToTopLeft() {
        let small = PanelPositioner.Screen(
            frame: CGRect(x: 0, y: 0, width: 500, height: 400),
            visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 400)
        )
        let origin = place(
            anchor: .mouse,
            mouseLocation: CGPoint(x: 250, y: 200),
            screens: [small]
        )

        #expect(origin == CGPoint(x: 0, y: 400 - 545))
    }

    private func place(
        anchor: PanelAnchor,
        statusItemRect: CGRect? = nil,
        mouseLocation: CGPoint = .zero,
        screens: [PanelPositioner.Screen]? = nil
    ) -> CGPoint {
        let screens = screens ?? [mainScreen]
        return PanelPositioner.origin(
            for: anchor,
            panelSize: panelSize,
            statusItemRect: statusItemRect,
            mouseLocation: mouseLocation,
            screens: screens,
            mainScreen: screens.first
        )
    }
}
