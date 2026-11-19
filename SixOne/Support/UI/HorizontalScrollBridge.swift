//
//  HorizontalScrollBridge.swift
//  SixOne
//
//  横向滚动桥：纵向滚轮转横向；分组拖拽到两端或窗口外时自动滚动。
//

import AppKit
import SwiftUI

/// 挂在横向 `ScrollView` 内容上，不绘制、不参与命中测试。
/// 横向 `ScrollView` 不处理纵向滚轮，鼠标滚轮悬在筛选条上会没反应。
struct HorizontalScrollBridge: NSViewRepresentable {
    /// 预览等模式下列表不可交互，把滚轮还给上面的预览。
    var isEnabled = true
    /// 目标横向偏移；与排序拖拽共用 SwiftUI `ScrollPosition`。
    var onHorizontalScroll: (CGFloat) -> Void = { _ in }
    /// 分组拖拽会话是否活跃；活跃时轮询指针做边缘自动滚动。
    var isDragging = false

    func makeNSView(context: Context) -> BridgeView {
        BridgeView(frame: .zero)
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onHorizontalScroll = onHorizontalScroll
        nsView.setDragging(isDragging)
    }

    final class BridgeView: NSView {
        /// 滚轮增量按行报告；放大到三行才跟手。
        private static let wheelLinesPerNotch: CGFloat = 3
        /// 拖到边缘后的自动滚动节拍。
        private static let autoScrollInterval: TimeInterval = 1.0 / 60.0
        /// 拖拽先移动这点距离再启用边缘滚动，避免抓在边上时立刻滚。
        private static let dragThreshold: CGFloat = 6

        var isEnabled = true
        var onHorizontalScroll: (CGFloat) -> Void = { _ in }

        /// 是否已挂上窗口级监听。
        var isMonitoringEvents: Bool { eventMonitor != nil }

        private var eventMonitor: Any?
        private var autoScrollTimer: Timer?
        private var autoScrollTarget: CGFloat?
        private var isDragging = false
        private var dragStartPointer: CGPoint?

        /// 桥只转发事件，点击要穿透到 chip。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else {
                removeMonitor()
                stopAutoScroll()
                return
            }
            installMonitor()
            if isDragging {
                startAutoScroll()
            }
        }

        isolated deinit {
            removeMonitor()
            stopAutoScroll()
        }

        // MARK: - 滚轮

        /// 纵向滚轮交给视图落位；不接管时返回 false。
        @discardableResult
        func scrollHorizontally(
            in scrollView: NSScrollView,
            verticalDelta: CGFloat,
            horizontalDelta: CGFloat,
            isPrecise: Bool
        ) -> Bool {
            guard let targetX = horizontalTarget(
                in: scrollView,
                verticalDelta: verticalDelta,
                horizontalDelta: horizontalDelta,
                isPrecise: isPrecise
            ) else { return false }
            // 到端点仍吞事件，但不必刷新滚动状态。
            if abs(targetX - scrollView.contentView.bounds.origin.x) > 0.5 {
                onHorizontalScroll(targetX)
            }
            return true
        }

        /// 换算目标横向偏移；横向手势、无溢出或分量更小时返回 nil。
        func horizontalTarget(
            in scrollView: NSScrollView,
            verticalDelta: CGFloat,
            horizontalDelta: CGFloat,
            isPrecise: Bool
        ) -> CGFloat? {
            // 横向手势保持系统行为；纵向分量更大时才接管。
            guard abs(verticalDelta) > abs(horizontalDelta) else { return nil }
            guard let documentView = scrollView.documentView else { return nil }

            let clipView = scrollView.contentView
            let maxOffset = max(0, documentView.frame.width - clipView.bounds.width)
            guard maxOffset > 0 else { return nil }

            let distance = isPrecise
                ? verticalDelta
                : verticalDelta * scrollView.horizontalLineScroll * Self.wheelLinesPerNotch
            return min(max(clipView.bounds.origin.x - distance, 0), maxOffset)
        }

        // MARK: - 监听

        private func installMonitor() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                guard let self, self.shouldHandle(event) else { return event }
                return nil
            }
        }

        private func removeMonitor() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            eventMonitor = nil
        }

        private func shouldHandle(_ event: NSEvent) -> Bool {
            guard isEnabled,
                  let window,
                  event.window === window,
                  let scrollView = enclosingScrollView
            else { return false }
            let point = scrollView.convert(event.locationInWindow, from: nil)
            guard scrollView.bounds.contains(point) else { return false }
            return scrollHorizontally(
                in: scrollView,
                verticalDelta: event.scrollingDeltaY,
                horizontalDelta: event.scrollingDeltaX,
                isPrecise: event.hasPreciseScrollingDeltas
            )
        }

        // MARK: - 拖拽到边缘时自动滚动

        func setDragging(_ dragging: Bool) {
            guard isDragging != dragging else { return }
            isDragging = dragging
            if dragging {
                startAutoScroll()
            } else {
                stopAutoScroll()
            }
        }

        private func startAutoScroll() {
            guard autoScrollTimer == nil else { return }
            dragStartPointer = nil
            autoScrollTarget = nil
            let timer = Timer(timeInterval: Self.autoScrollInterval, repeats: true) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.autoScrollTick() }
            }
            // 拖拽会话跑在事件跟踪模式里，必须进 common modes 才会继续触发。
            RunLoop.main.add(timer, forMode: .common)
            autoScrollTimer = timer
        }

        private func stopAutoScroll() {
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
            autoScrollTarget = nil
            dragStartPointer = nil
        }

        private func autoScrollTick() {
            guard isDragging else {
                stopAutoScroll()
                return
            }
            guard let window,
                  let scrollView = enclosingScrollView,
                  let documentView = scrollView.documentView
            else { return }
            let clipView = scrollView.contentView
            let viewWidth = clipView.bounds.width
            let maxOffset = max(0, documentView.frame.width - viewWidth)
            guard maxOffset > 0 else { return }

            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let point = scrollView.convert(windowPoint, from: nil)
            guard let start = dragStartPointer else {
                dragStartPointer = point
                return
            }
            guard hypot(point.x - start.x, point.y - start.y) > Self.dragThreshold else {
                return
            }
            guard let intent = ReorderAutoScroll.intent(
                locationX: point.x,
                viewWidth: viewWidth
            ) else {
                // 回到中间就停下；再次靠近边缘时按实际位置续上。
                autoScrollTarget = nil
                return
            }

            let current = autoScrollTarget ?? clipView.bounds.origin.x
            let target = ReorderAutoScroll.nextOffset(
                current: current,
                direction: intent.direction,
                penetration: intent.penetration,
                maxOffset: maxOffset
            )
            guard abs(target - current) > 0.5 else { return }
            autoScrollTarget = target
            onHorizontalScroll(target)
        }
    }
}

/// 拖到视口两端时的自动滚动：越靠外越快，到端点停住。
nonisolated enum ReorderAutoScroll {
    /// 视口两端触发自动滚动的宽度。
    static let edgeZone: CGFloat = 20
    static let baseStep: CGFloat = 6
    static let maxStep: CGFloat = 32
    private static let acceleration: CGFloat = 1

    struct Intent: Equatable {
        var direction: CGFloat
        var penetration: CGFloat
    }

    /// 指针落在边缘区时给出滚动方向与深度；中间返回 nil。
    static func intent(locationX: CGFloat, viewWidth: CGFloat) -> Intent? {
        guard viewWidth > 0 else { return nil }
        if locationX < edgeZone {
            return Intent(direction: -1, penetration: edgeZone - locationX)
        }
        if locationX > viewWidth - edgeZone {
            return Intent(direction: 1, penetration: locationX - (viewWidth - edgeZone))
        }
        return nil
    }

    /// 单次节拍的步长。
    static func step(penetration: CGFloat) -> CGFloat {
        min(baseStep + max(0, penetration) * acceleration, maxStep)
    }

    /// 朝拖拽方向推进一次，夹在 `[0, maxOffset]` 内。
    static func nextOffset(
        current: CGFloat,
        direction: CGFloat,
        penetration: CGFloat,
        maxOffset: CGFloat
    ) -> CGFloat {
        guard direction != 0 else { return current }
        let moved = current + direction * step(penetration: penetration)
        return min(max(moved, 0), maxOffset)
    }
}
