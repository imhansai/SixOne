//
//  RowInteractionHostTests.swift
//  SixOneTests
//  行点击：单击抬手即选中，双击先选中再激活，拖出取消而应用挪走仍算。

import AppKit
import Testing
@testable import SixOne

@Suite("行点击的行为")
@MainActor
struct RowInteractionHostTests {
    private final class Recorder {
        var events: [String] = []
        var activatedIDs: [UUID] = []
        var plainTextFlags: [Bool] = []
    }

    private func makeHost(
        width: CGFloat = 200,
        height: CGFloat = 58
    ) -> (RowInteractionHost.HostView, NSWindow) {
        let view = RowInteractionHost.HostView()
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFrontRegardless()
        return (view, window)
    }

    @discardableResult
    private func configure(
        _ view: RowInteractionHost.HostView,
        recorder: Recorder,
        rowID: UUID = UUID()
    ) -> UUID {
        view.currentRowID = rowID
        // 独立使用时无共享追踪器，回调挂在宿主自带的追踪器上。
        view.localClickTracker.onSelect = { _ in recorder.events.append("select") }
        view.localClickTracker.onActivate = { id, asPlainText in
            recorder.events.append("activate")
            recorder.activatedIDs.append(id)
            recorder.plainTextFlags.append(asPlainText)
        }
        return rowID
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        in window: NSWindow,
        at point: CGPoint,
        clickCount: Int,
        timestamp: TimeInterval? = nil,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: modifiers,
            timestamp: timestamp ?? ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        )!
    }

    @Test("单击：抬手立即选中，不等双击窗口")
    func singleClickSelectsOnMouseUp() {
        let recorder = Recorder()
        let (view, window) = makeHost()
        defer { window.orderOut(nil) }
        configure(view, recorder: recorder)

        let point = CGPoint(x: 100, y: 29)
        view.mouseDown(with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 1))
        view.mouseUp(with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: 1))

        #expect(recorder.events == ["select"], "单击应当同步选中，不能等双击判定窗口")
    }

    @Test("双击：第一下选中，第二下激活（不再重复选中）")
    func doubleClickSelectsThenActivates() {
        let recorder = Recorder()
        let (view, window) = makeHost()
        defer { window.orderOut(nil) }
        let rowID = configure(view, recorder: recorder)

        let point = CGPoint(x: 100, y: 29)
        view.mouseDown(with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 1))
        view.mouseUp(with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: 1))
        view.mouseDown(with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 2))
        view.mouseUp(with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: 2))

        #expect(recorder.events == ["select", "activate"])
        #expect(recorder.activatedIDs == [rowID])
        #expect(recorder.plainTextFlags == [false])
    }

    @Test("⇧+双击：激活时带上纯文本意图")
    func shiftDoubleClickRequestsPlainText() {
        let recorder = Recorder()
        let (view, window) = makeHost()
        defer { window.orderOut(nil) }
        configure(view, recorder: recorder)

        let point = CGPoint(x: 100, y: 29)
        view.mouseDown(with: mouseEvent(
            .leftMouseDown, in: window, at: point, clickCount: 1, modifiers: .shift
        ))
        view.mouseUp(with: mouseEvent(
            .leftMouseUp, in: window, at: point, clickCount: 1, modifiers: .shift
        ))
        view.mouseDown(with: mouseEvent(
            .leftMouseDown, in: window, at: point, clickCount: 2, modifiers: .shift
        ))
        view.mouseUp(with: mouseEvent(
            .leftMouseUp, in: window, at: point, clickCount: 2, modifiers: .shift
        ))

        #expect(recorder.events == ["select", "activate"])
        #expect(recorder.plainTextFlags == [true])
    }

    @Test("按下后拖出行外再抬起：不算点击")
    func dragOutCancelsClick() {
        let recorder = Recorder()
        let (view, window) = makeHost()
        defer { window.orderOut(nil) }
        configure(view, recorder: recorder)

        view.mouseDown(
            with: mouseEvent(.leftMouseDown, in: window, at: CGPoint(x: 100, y: 29), clickCount: 1)
        )
        view.mouseUp(
            with: mouseEvent(.leftMouseUp, in: window, at: CGPoint(x: 250, y: 29), clickCount: 1)
        )

        #expect(recorder.events.isEmpty)
    }

    @Test("行被应用挪走、指针没动：抬起仍算点击")
    func rowMovedUnderStationaryPointerStillClicks() {
        let recorder = Recorder()
        let (view, window) = makeHost()
        defer { window.orderOut(nil) }
        configure(view, recorder: recorder)

        let point = CGPoint(x: 100, y: 29)
        view.mouseDown(with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 1))
        // 补齐留白使行整体上移，抬起点已在行外。
        view.frame.origin = NSPoint(x: 0, y: -40)
        view.mouseUp(with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: 1))

        #expect(recorder.events == ["select"], "行被应用挪走不该被当成拖出取消")
    }

    @Test("双击第二下：行已被补齐留白挪走，激活的仍是第一下那一条")
    func secondClickActivatesSequenceAnchor() {
        let recorder = Recorder()
        let (view, window) = makeHost()
        defer { window.orderOut(nil) }
        let rowID = configure(view, recorder: recorder)

        let point = CGPoint(x: 100, y: 29)
        view.mouseDown(with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 1))
        view.mouseUp(with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: 1))
        view.frame.origin = NSPoint(x: 0, y: -40)

        view.mouseDown(with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 2))
        view.mouseUp(with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: 2))

        #expect(recorder.events == ["select", "activate"])
        #expect(recorder.activatedIDs == [rowID], "第二下被丢掉，或激活了别的行")
    }

    @Test("双击第二下指针自己拖出行外：不激活")
    func secondClickDraggedOutDoesNotActivate() {
        let recorder = Recorder()
        let (view, window) = makeHost()
        defer { window.orderOut(nil) }
        configure(view, recorder: recorder)

        let point = CGPoint(x: 100, y: 29)
        view.mouseDown(with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 1))
        view.mouseUp(with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: 1))
        view.mouseDown(with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 2))
        view.mouseUp(
            with: mouseEvent(.leftMouseUp, in: window, at: CGPoint(x: 300, y: 29), clickCount: 2)
        )

        #expect(recorder.events == ["select"])
    }

    @Test("两击之间行被重绑：激活的仍是第一下那一条")
    func anchorSurvivesRebindBetweenClicks() {
        let recorder = Recorder()
        let (view, window) = makeHost()
        defer { window.orderOut(nil) }
        let anchor = configure(view, recorder: recorder)

        let point = CGPoint(x: 100, y: 29)
        view.mouseDown(with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 1))
        view.mouseUp(with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: 1))
        view.currentRowID = UUID()

        view.mouseDown(with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 2))
        view.mouseUp(with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: 2))

        #expect(recorder.activatedIDs == [anchor], "激活目标跟着脚下走，而不是跟着连击起点走")
    }

    /// 刚失去 key 时第一下可能被吞，第二下带回旧锚点，不能拿它当激活目标。
    @Test("连击第一下没送达（锚点过期）：激活脚下这一行")
    func staleAnchorFallsBackToCurrentRow() {
        let recorder = Recorder()
        let (view, window) = makeHost()
        defer { window.orderOut(nil) }
        configure(view, recorder: recorder)

        let point = CGPoint(x: 100, y: 29)
        let start = ProcessInfo.processInfo.systemUptime
        view.mouseDown(
            with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 1, timestamp: start)
        )
        view.mouseUp(
            with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: 1, timestamp: start + 0.05)
        )
        let rebound = UUID()
        view.currentRowID = rebound

        let late = start + NSEvent.doubleClickInterval + 1
        view.mouseDown(
            with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 2, timestamp: late)
        )
        view.mouseUp(
            with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: 2, timestamp: late + 0.05)
        )

        #expect(recorder.activatedIDs == [rebound], "过期锚点被当成了激活目标")
    }
}
