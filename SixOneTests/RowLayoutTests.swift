//
//  RowLayoutTests.swift
//  SixOneTests

import AppKit
import CoreGraphics
import Testing
@testable import SixOne

@Suite("行尾操作列的宽度")
struct RowLayoutTests {
    private let rowBounds = CGRect(x: 0, y: 0, width: 640, height: ClipboardLayout.rowHeight)

    @Test("列宽 = 按钮 + 尾部内缩，按钮因此落在行尾那个内缩处")
    func columnWidthMatchesButtonPlacement() {
        for usesOverlay in [true, false] {
            let inset = ClipboardLayout.rowCopyButtonTrailingInset(usesOverlayScrollers: usesOverlay)
            let column = ClipboardLayout.rowCopyButtonColumnWidth(usesOverlayScrollers: usesOverlay)
            #expect(rowBounds.maxX - column + ClipboardLayout.rowCopyButtonSize == rowBounds.maxX - inset)
        }
    }

    @Test("最窄的行也放得下这一列")
    func columnFitsNarrowRow() {
        for usesOverlay in [true, false] {
            let column = ClipboardLayout.rowCopyButtonColumnWidth(usesOverlayScrollers: usesOverlay)
            #expect(column < 320)
            #expect(320 - column >= 40)
        }
    }
}

/// 行尾内缩按滚动条形态取值；不能翻转 `preferredScrollerStyle`，那会改用户设置。
@Suite("行尾内缩按滚动条形态取值")
struct RowSelectionInsetTests {
    @Test("浮层样式：高亮尾部让开滑块，按钮再进一个基准边距")
    func overlayInsetsClearKnob() {
        let selection = ClipboardLayout.rowSelectionTrailingInset(usesOverlayScrollers: true)
        let button = ClipboardLayout.rowCopyButtonTrailingInset(usesOverlayScrollers: true)
        #expect(selection > ClipboardLayout.overlayScrollerKnobClearance)
        #expect(selection == ClipboardLayout.overlayScrollerKnobClearance + 2)
        #expect(button == selection + ClipboardLayout.rowHorizontalInset)
    }

    @Test("传统样式：滚动条占布局宽度，高亮按基准边距、左右对称")
    func legacyInsetsUseBaseInset() {
        #expect(
            ClipboardLayout.rowSelectionTrailingInset(usesOverlayScrollers: false)
                == ClipboardLayout.rowHorizontalInset
        )
        #expect(
            ClipboardLayout.rowCopyButtonTrailingInset(usesOverlayScrollers: false)
                == ClipboardLayout.overlayScrollerKnobClearance + 2
        )
    }

    @Test("复制按钮整套落在高亮里")
    func copyButtonSitsInsideHighlight() {
        for usesOverlay in [true, false] {
            let selection = ClipboardLayout.rowSelectionTrailingInset(usesOverlayScrollers: usesOverlay)
            for width in [CGFloat(320), 640, 1024] {
                let column = ClipboardLayout.rowCopyButtonColumnWidth(usesOverlayScrollers: usesOverlay)
                let buttonMinX = width - column
                let buttonMaxX = buttonMinX + ClipboardLayout.rowCopyButtonSize
                #expect(buttonMaxX <= width - selection)
                #expect(buttonMinX >= ClipboardLayout.rowHorizontalInset)
            }
        }
    }
}
