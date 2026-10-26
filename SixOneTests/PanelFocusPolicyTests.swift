//
//  PanelFocusPolicyTests.swift
//  SixOneTests

import Testing
@testable import SixOne

@Suite("面板焦点判定")
struct PanelFocusPolicyTests {
    private func snapshot(_ configure: (inout PanelFocusSnapshot) -> Void) -> PanelFocusSnapshot {
        var snapshot = PanelFocusSnapshot()
        configure(&snapshot)
        return snapshot
    }

    @Test("默认现场（切到别的应用、面板不是 key）收起")
    func baselineHides() {
        #expect(PanelFocusPolicy.shouldHide(snapshot { _ in }))
    }

    @Test("分享进行中不收起，即使用户点了面板外面")
    func sharingKeepsPanel() {
        #expect(!PanelFocusPolicy.shouldHide(snapshot {
            $0.isSharing = true
            $0.clickedOutside = true
            $0.isAppFrontmost = false
        }))
    }

    @Test("面板挂着 sheet 不收起")
    func attachedSheetKeepsPanel() {
        #expect(!PanelFocusPolicy.shouldHide(snapshot {
            $0.hasAttachedSheet = true
            $0.isAppFrontmost = false
        }))
    }

    @Test("用户正按着菜单栏图标时不收起：开关由抬起的按钮动作负责")
    func pressingStatusItemKeepsPanel() {
        // 点图标那一拍：应用可能已失活，key 也可能被状态栏窗口接管。
        #expect(!PanelFocusPolicy.shouldHide(snapshot {
            $0.isPressingStatusItem = true
            $0.isAppFrontmost = false
            $0.hasKeyWindow = true
            $0.clickedOutside = true
        }))
    }

    @Test("应用在最前、面板是 key：焦点没被夺走，不收起")
    func focusStillInsideKeepsPanel() {
        #expect(!PanelFocusPolicy.shouldHide(snapshot {
            $0.isAppFrontmost = true
            $0.isPanelKeyWindow = true
        }))
    }

    @Test("字体 / 颜色面板接管 key 时不收起")
    func textAuxiliaryPanelKeepsPanel() {
        #expect(!PanelFocusPolicy.shouldHide(snapshot {
            $0.isAppFrontmost = true
            $0.isTextAuxiliaryPanelKey = true
        }))
    }

    @Test("本应用其他窗口显示 sheet 时不收起")
    func applicationSheetKeepsPanel() {
        #expect(!PanelFocusPolicy.shouldHide(snapshot {
            $0.isAppFrontmost = true
            $0.hasApplicationSheet = true
        }))
    }

    @Test("编辑中、前台是系统辅助进程时不收起（自动填充选择器 / Touch ID）")
    func editingWithSystemHelperKeepsPanel() {
        #expect(!PanelFocusPolicy.shouldHide(snapshot {
            $0.isEditingText = true
            $0.isSystemHelperFrontmost = true
            $0.isAppFrontmost = false
        }))
    }

    @Test("用户主动点了面板外面时，辅助进程前台也要收起")
    func clickedOutsideHidesEvenWhileEditing() {
        #expect(PanelFocusPolicy.shouldHide(snapshot {
            $0.isEditingText = true
            $0.isSystemHelperFrontmost = true
            $0.clickedOutside = true
            $0.isAppFrontmost = false
        }))
    }

    @Test("没在编辑时，辅助进程前台不构成保留理由")
    func systemHelperWithoutEditingHides() {
        #expect(PanelFocusPolicy.shouldHide(snapshot {
            $0.isSystemHelperFrontmost = true
            $0.isAppFrontmost = false
        }))
    }

    @Test("应用在最前但没有 key 窗口（key 正在切换）时不收起")
    func keyWindowInFlightKeepsPanel() {
        #expect(!PanelFocusPolicy.shouldHide(snapshot {
            $0.isAppFrontmost = true
            $0.hasKeyWindow = false
        }))
    }

    @Test("焦点被本应用其他窗口（设置窗口）接管时收起")
    func otherApplicationWindowHides() {
        #expect(PanelFocusPolicy.shouldHide(snapshot {
            $0.isAppFrontmost = true
            $0.hasKeyWindow = true
            $0.isPanelKeyWindow = false
        }))
    }
}
