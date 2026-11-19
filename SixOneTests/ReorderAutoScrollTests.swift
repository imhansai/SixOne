//
//  ReorderAutoScrollTests.swift
//  SixOneTests
//  分组拖到视口两端时的自动滚动换算。
//

import CoreGraphics
import Testing
@testable import SixOne

@Suite("拖拽自动滚动")
struct ReorderAutoScrollTests {
    private let viewWidth: CGFloat = 400

    private func intent(at x: CGFloat, width: CGFloat? = nil) -> ReorderAutoScroll.Intent? {
        ReorderAutoScroll.intent(locationX: x, viewWidth: width ?? viewWidth)
    }

    private func next(
        _ current: CGFloat,
        direction: CGFloat,
        penetration: CGFloat = 0,
        maxOffset: CGFloat = 500
    ) -> CGFloat {
        ReorderAutoScroll.nextOffset(
            current: current,
            direction: direction,
            penetration: penetration,
            maxOffset: maxOffset
        )
    }

    @Test("两端边缘区触发，中间不滚")
    func intentTriggersAtEdges() {
        #expect(intent(at: 0)?.direction == -1)
        #expect(intent(at: viewWidth)?.direction == 1)
        #expect(intent(at: viewWidth / 2) == nil)
        #expect(intent(at: -40)?.direction == -1, "拖出窗口左边仍要滚")
        #expect(intent(at: viewWidth + 40)?.direction == 1, "拖出窗口右边仍要滚")
        #expect(intent(at: 0, width: 0) == nil)
    }

    @Test("越靠外滚得越快，封顶")
    func stepGrowsThenCaps() {
        #expect(ReorderAutoScroll.step(penetration: 0) == ReorderAutoScroll.baseStep)
        #expect(ReorderAutoScroll.step(penetration: 10) > ReorderAutoScroll.baseStep)
        #expect(ReorderAutoScroll.step(penetration: 10_000) == ReorderAutoScroll.maxStep)
    }

    @Test("朝拖拽方向推进并夹在两端")
    func nextOffsetClampsAtBounds() {
        #expect(next(100, direction: 1) == 106)
        #expect(next(5, direction: -1) == 0)
        #expect(next(495, direction: 1, penetration: 10_000) == 500)
        #expect(next(0, direction: -1, penetration: 10) == 0)
    }

    @Test("到端点后再推进也停在端点")
    func staysAtBoundary() {
        var offset: CGFloat = 0
        for _ in 0..<100 {
            offset = next(offset, direction: 1)
        }
        #expect(offset == 500)
    }

    @Test("没有方向时不移动")
    func zeroDirectionKeepsOffset() {
        #expect(next(123, direction: 0, penetration: 30) == 123)
    }
}
