//
//  RowCopyHitTargetTests.swift
//  SixOneTests

import AppKit
import Testing
@testable import SixOne

@Suite("复制命中目标的点击行为")
@MainActor
struct RowCopyHitTargetTests {
    private final class Recorder {
        var copies = 0
    }

    private func makeTarget() -> (RowCopyHitTarget.HostView, NSWindow) {
        let size = ClipboardLayout.rowCopyButtonSize
        let view = RowCopyHitTarget.HostView()
        view.frame = NSRect(x: 0, y: 0, width: size, height: size)
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: size, height: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFrontRegardless()
        return (view, window)
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        in window: NSWindow,
        at point: CGPoint,
        clickCount: Int
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        )!
    }

    private func click(
        _ view: RowCopyHitTarget.HostView,
        in window: NSWindow,
        at point: CGPoint,
        clickCount: Int
    ) {
        view.mouseDown(with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: clickCount))
        view.mouseUp(with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: clickCount))
    }

    @Test("单击复制一次")
    func singleClickCopiesOnce() {
        let recorder = Recorder()
        let (view, window) = makeTarget()
        defer { window.orderOut(nil) }
        view.onCopy = { recorder.copies += 1 }

        click(view, in: window, at: CGPoint(x: 13, y: 13), clickCount: 1)

        #expect(recorder.copies == 1)
    }

    @Test("双击也只复制一次")
    func doubleClickCopiesOnce() {
        let recorder = Recorder()
        let (view, window) = makeTarget()
        defer { window.orderOut(nil) }
        view.onCopy = { recorder.copies += 1 }

        click(view, in: window, at: CGPoint(x: 13, y: 13), clickCount: 1)
        click(view, in: window, at: CGPoint(x: 13, y: 13), clickCount: 2)

        #expect(recorder.copies == 1, "双击复制按钮不该复制两次")
    }

    @Test("两次分开的单击各自复制")
    func separateClicksCopyEachTime() {
        let recorder = Recorder()
        let (view, window) = makeTarget()
        defer { window.orderOut(nil) }
        view.onCopy = { recorder.copies += 1 }

        click(view, in: window, at: CGPoint(x: 13, y: 13), clickCount: 1)
        click(view, in: window, at: CGPoint(x: 13, y: 13), clickCount: 1)

        #expect(recorder.copies == 2)
    }

    @Test("按下后拖出按钮再抬起：不复制")
    func dragOutCancelsCopy() {
        let recorder = Recorder()
        let (view, window) = makeTarget()
        defer { window.orderOut(nil) }
        view.onCopy = { recorder.copies += 1 }

        view.mouseDown(
            with: mouseEvent(.leftMouseDown, in: window, at: CGPoint(x: 13, y: 13), clickCount: 1)
        )
        view.mouseUp(
            with: mouseEvent(.leftMouseUp, in: window, at: CGPoint(x: 40, y: 13), clickCount: 1)
        )

        #expect(recorder.copies == 0)
    }

    @Test("按下后行被应用挪走、指针没动：仍复制")
    func movedTargetUnderStationaryPointerStillCopies() {
        let recorder = Recorder()
        let (view, window) = makeTarget()
        defer { window.orderOut(nil) }
        view.onCopy = { recorder.copies += 1 }

        let point = CGPoint(x: 13, y: 13)
        view.mouseDown(with: mouseEvent(.leftMouseDown, in: window, at: point, clickCount: 1))
        view.frame.origin = NSPoint(x: 0, y: -20)
        view.mouseUp(with: mouseEvent(.leftMouseUp, in: window, at: point, clickCount: 1))

        #expect(recorder.copies == 1)
    }
}
