//
//  HorizontalScrollBridge.swift
//  SixOne
//
//  横向滚动桥：纵向滚轮转横向；只转发事件，不绘制、不参与命中测试。
//

import AppKit
import SwiftUI

/// 挂在横向 `ScrollView` 内容上。横向 `ScrollView` 不处理纵向滚轮，
/// 鼠标滚轮悬在筛选条上会没反应。
struct HorizontalScrollBridge: NSViewRepresentable {
    /// 预览等模式下列表不可交互，把滚轮还给上面的预览。
    var isEnabled = true
    /// 目标横向偏移；与 SwiftUI `ScrollPosition` 共用。
    var onHorizontalScroll: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> BridgeView {
        BridgeView(frame: .zero)
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onHorizontalScroll = onHorizontalScroll
    }

    final class BridgeView: NSView {
        /// 滚轮增量按行报告；放大到三行才跟手。
        private static let wheelLinesPerNotch: CGFloat = 3

        var isEnabled = true
        var onHorizontalScroll: (CGFloat) -> Void = { _ in }

        /// 是否已挂上窗口级监听。
        var isMonitoringEvents: Bool { eventMonitor != nil }

        private var eventMonitor: Any?

        /// 桥只转发事件，点击要穿透到 chip。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                installMonitor()
            } else {
                removeMonitor()
            }
        }

        isolated deinit {
            removeMonitor()
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
    }
}
