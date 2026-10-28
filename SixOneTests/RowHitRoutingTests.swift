//
//  RowHitRoutingTests.swift
//  SixOneTests
//  行鼠标路由集成回归：用 postEvent 派发（sendEvent 不设 currentEvent），按回调等待。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

/// 用例会让窗口成为 key window（进程级状态），故串行跑。
@Suite("行的鼠标路由", .serialized)
@MainActor
struct RowHitRoutingTests {
    private final class Recorder {
        var events: [String] = []
        var menuRequests = 0
    }

    @Test("按钮、按钮外与右键各走各的层")
    func hitRouting() async throws {
        let harness = try ClipboardHarness()
        let context = PanelContext(
            manager: harness.manager,
            store: HistoryListStore(repository: FakeHistoryRepository(), events: ClipboardHistoryEventBus()),
            caches: PanelCaches()
        )
        let recorder = Recorder()
        let row = HistoryRow(ClipboardItem(kind: .text, text: "routing"))
        let size = NSSize(width: ClipboardLayout.panelWidth, height: ClipboardLayout.rowHeight)

        let host = NSHostingView(rootView: AnyView(
            ClipboardRowView(
                row: row,
                isSelected: false,
                isListActive: false,
                onSelect: { _ in recorder.events.append("select") },
                onActivate: { _, _ in recorder.events.append("activate") },
                onCopy: { recorder.events.append("copy") },
                menuProvider: { _ in
                    recorder.menuRequests += 1
                    return nil
                }
            )
            .frame(width: size.width, height: size.height)
            .environment(context)
        ))
        host.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFrontRegardless()
        window.makeKey()
        host.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        let mounted = await Wait.until {
            let views = OffscreenHost.allSubviews(of: host)
            return views.contains { $0 is RowCopyHitTarget.HostView }
                && views.contains { $0 is RowInteractionHost.HostView }
        }
        #expect(mounted, "两层命中视图没有挂好")

        let target = try #require(
            OffscreenHost.allSubviews(of: host).compactMap { $0 as? RowCopyHitTarget.HostView }.first,
            "没找到复制命中目标"
        )
        let rowHost = try #require(
            OffscreenHost.allSubviews(of: host).compactMap { $0 as? RowInteractionHost.HostView }
                .max { $0.bounds.width < $1.bounds.width },
            "没找到整行宿主"
        )
        let buttonPoint = target.convert(
            CGPoint(x: target.bounds.midX, y: target.bounds.midY),
            to: nil
        )
        let gutterPoint = rowHost.convert(
            CGPoint(x: rowHost.bounds.maxX - 10, y: rowHost.bounds.midY),
            to: nil
        )

        // 判据是手势该产生的回调；队列 FIFO，等到即表示前面事件已处理完。

        click(window, at: buttonPoint, clickCount: 1)
        let copied = await Wait.until { !recorder.events.isEmpty }
        #expect(copied, "按钮单击没有产生回调")
        #expect(recorder.events == ["copy"], "按钮单击应当只复制")

        recorder.events.removeAll()
        doubleClick(window, at: buttonPoint)
        click(window, at: gutterPoint, clickCount: 1)
        let flushed = await Wait.until { recorder.events.count >= 2 }
        #expect(flushed, "哨兵单击没有产生回调")
        #expect(recorder.events == ["copy", "select"], "按钮双击也只复制一次")

        recorder.events.removeAll()
        click(window, at: gutterPoint, clickCount: 1)
        let selected = await Wait.until { !recorder.events.isEmpty }
        #expect(selected, "按钮外单击没有产生回调")
        #expect(recorder.events == ["select"], "按钮外单击应当立即选中")

        recorder.events.removeAll()
        doubleClick(window, at: gutterPoint)
        let activated = await Wait.until { recorder.events.contains("activate") }
        #expect(activated, "按钮外双击没有激活")
        #expect(recorder.events == ["select", "activate"], "按钮外双击应当选中后激活")

        rightClick(window, at: buttonPoint)
        let menuRequested = await Wait.until { recorder.menuRequests > 0 }
        #expect(menuRequested, "右键没有请求菜单")
        #expect(recorder.menuRequests == 1, "按钮上的右键应当穿透到行菜单")
    }

    // MARK: - 合成事件

    private func click(_ window: NSWindow, at point: NSPoint, clickCount: Int) {
        post(window, .leftMouseDown, at: point, clickCount: clickCount)
        post(window, .leftMouseUp, at: point, clickCount: clickCount)
    }

    private func doubleClick(_ window: NSWindow, at point: NSPoint) {
        post(window, .leftMouseDown, at: point, clickCount: 1)
        post(window, .leftMouseUp, at: point, clickCount: 1)
        post(window, .leftMouseDown, at: point, clickCount: 2)
        post(window, .leftMouseUp, at: point, clickCount: 2)
    }

    private func rightClick(_ window: NSWindow, at point: NSPoint) {
        post(window, .rightMouseDown, at: point, clickCount: 1)
    }

    private func post(_ window: NSWindow, _ type: NSEvent.EventType, at point: NSPoint, clickCount: Int) {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        ) else {
            Issue.record("合成 \(type) 事件失败")
            return
        }
        NSApp.postEvent(event, atStart: false)
    }
}
