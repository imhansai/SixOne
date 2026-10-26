//
//  RowHitPolicyTests.swift
//  SixOneTests

import AppKit
import Testing
@testable import SixOne

@Suite("行交互宿主的命中策略")
struct RowHitPolicyTests {
    @Test("点击完成：仍指在行内算，指针没动也算")
    func completesClickWhenPointerHeldStill() {
        #expect(RowHitPolicy.completesClick(releaseInsideRow: true, pointerTravel: 0))
        #expect(RowHitPolicy.completesClick(releaseInsideRow: false, pointerTravel: 0))
        #expect(
            RowHitPolicy.completesClick(
                releaseInsideRow: false,
                pointerTravel: RowHitPolicy.clickPointerSlop
            )
        )
    }

    @Test("点击完成：指针自己拖出行外不算")
    func completesClickRejectsDragOut() {
        #expect(!RowHitPolicy.completesClick(releaseInsideRow: false, pointerTravel: 150))
        #expect(
            !RowHitPolicy.completesClick(
                releaseInsideRow: false,
                pointerTravel: RowHitPolicy.clickPointerSlop + 1
            )
        )
        #expect(RowHitPolicy.completesClick(releaseInsideRow: true, pointerTravel: 300))
    }

    @Test("行宿主：鼠标按下/抬起都接管")
    func rowHostClaimsMouseEvents() {
        for type in [
            NSEvent.EventType.leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
        ] {
            #expect(RowHitPolicy.claims(type: type))
        }
    }

    @Test("行宿主：非鼠标事件一律放行")
    func rowHostPassesNonMouseEvents() {
        for type in [NSEvent.EventType.keyDown, .keyUp, .mouseMoved, .scrollWheel, .flagsChanged] {
            #expect(!RowHitPolicy.claims(type: type))
        }
    }

    @Test("复制命中目标：只认普通左键")
    func copyTargetClaimsOnlyPlainLeftClicks() {
        #expect(RowHitPolicy.isPlainLeftClick(.leftMouseDown, modifiers: []))
        #expect(RowHitPolicy.isPlainLeftClick(.leftMouseUp, modifiers: []))
        #expect(!RowHitPolicy.isPlainLeftClick(.leftMouseDown, modifiers: [.control]))
        #expect(!RowHitPolicy.isPlainLeftClick(.leftMouseUp, modifiers: [.control]))
        #expect(!RowHitPolicy.isPlainLeftClick(.rightMouseDown, modifiers: []))
        #expect(!RowHitPolicy.isPlainLeftClick(.rightMouseUp, modifiers: []))
        #expect(!RowHitPolicy.isPlainLeftClick(.otherMouseDown, modifiers: []))
        #expect(!RowHitPolicy.isPlainLeftClick(.mouseMoved, modifiers: []))
    }
}
