//
//  RowClickGestureContinuityTests.swift
//  SixOneTests
//  行点击按按下时的条目落定（跨复用/重建），同 id 内容变化须原位刷新。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("行点击手势的连续性")
@MainActor
struct RowClickGestureContinuityTests {
    private static let viewportSize = NSSize(width: ClipboardLayout.panelWidth, height: 545)

    private final class Recorder {
        var selections: [UUID] = []
        var activations: [UUID] = []
    }

    private func makeRows(_ count: Int) -> [HistoryRow] {
        (0..<count).map { HistoryRow.stub(title: "第 \($0) 行") }
    }

    private func makeView(
        _ context: PanelContext,
        rows: [HistoryRow],
        dataRevision: Int,
        recorder: Recorder
    ) -> AnyView {
        AnyView(
            HistoryListTableView(
                context: context,
                rows: rows,
                dataRevision: dataRevision,
                locale: Locale(identifier: "en"),
                selectedItemID: nil,
                scrollRevision: 0,
                onSelect: { recorder.selections.append($0) },
                onActivate: { id, _ in recorder.activations.append(id) },
                onCopy: { _ in },
                menuProvider: { _, _ in nil }
            )
        )
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        in window: NSWindow,
        at point: NSPoint,
        number: Int
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: number,
            clickCount: 1,
            pressure: 1
        )!
    }

    @Test("抬起落到另一行宿主上，选中的仍是按下时的条目")
    func sharedTrackerKeepsPressedRow() throws {
        let recorder = Recorder()
        let pressedRow = UUID()
        let reboundRow = UUID()
        let tracker = RowClickTracker()
        tracker.onSelect = { recorder.selections.append($0) }

        let first = RowInteractionHost.HostView()
        first.clickTracker = tracker
        first.currentRowID = pressedRow
        let second = RowInteractionHost.HostView()
        second.clickTracker = tracker
        second.currentRowID = reboundRow

        let point = NSPoint(x: 40, y: 20)
        let down = NSEvent.mouseEvent(
            with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        )!
        first.mouseDown(with: down)
        let up = NSEvent.mouseEvent(
            with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 1
        )!
        second.mouseUp(with: up)

        #expect(recorder.selections == [pressedRow], "点击跟着抬起时的视图走了")
    }

    @Test("整表重建夹在按下与抬起之间，点击不丢")
    func clickSurvivesReloadBetweenDownAndUp() async throws {
        let context = try TestPanel.context()
        let recorder = Recorder()
        let rows = makeRows(200)
        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, dataRevision: 0, recorder: recorder),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host))
        let table = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { table.numberOfRows == rows.count })

        let hosts = OffscreenHost.allSubviews(of: host)
            .compactMap { $0 as? RowInteractionHost.HostView }
            .filter { $0.bounds.width > 100 }
        let target = try #require(hosts.first)
        let point = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
        let pressedID = target.currentRowID
        let tracker = try #require(target.clickTracker)

        NSApp.postEvent(mouseEvent(.leftMouseDown, in: window, at: point, number: 1), atStart: false)
        // 等按下被收下再重建，否则测的可能是「按下发生在重建之后」。
        let began = await Wait.until(timeout: .seconds(1), interval: .milliseconds(5)) {
            tracker.pressedRowID == pressedID
        }
        #expect(began, "按下没有被行宿主收下，用例前提不成立")

        let reordered = Array(rows.dropFirst()) + [rows[0]]
        host.rootView = makeView(
            context, rows: reordered, dataRevision: 1, recorder: recorder
        )
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(30))

        NSApp.postEvent(mouseEvent(.leftMouseUp, in: window, at: point, number: 2), atStart: false)
        let landed = await Wait.until(timeout: .seconds(1), interval: .milliseconds(5)) {
            !recorder.selections.isEmpty
        }
        #expect(landed, "整表重建把这次点击吞掉了")
        #expect(recorder.selections == [pressedID], "点击跟着重建后的行走了")
    }

    @Test("同 id 的行内容变化不整表重建")
    func contentChangeUpdatesInPlace() async throws {
        let context = try TestPanel.context()
        let recorder = Recorder()
        let rows = makeRows(200)
        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, dataRevision: 0, recorder: recorder),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host))
        let table = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { table.numberOfRows == rows.count })

        let cellBefore = try #require(table.view(atColumn: 0, row: 0, makeIfNecessary: false))
        let hostViewsBefore = OffscreenHost.allSubviews(of: host)
            .compactMap { $0 as? RowInteractionHost.HostView }
            .map(ObjectIdentifier.init)

        var updated = rows
        let old = updated[0]
        updated[0] = HistoryRow(
            id: old.id, kind: old.kind, title: "标题已更新", filePath: old.filePath,
            fileCount: old.fileCount, contentType: old.contentType,
            thumbnailData: old.thumbnailData,
            thumbnailVersion: old.thumbnailVersion,
            sourceAppBundleIdentifier: old.sourceAppBundleIdentifier,
            lastActivityAt: old.lastActivityAt
        )
        host.rootView = makeView(context, rows: updated, dataRevision: 1, recorder: recorder)
        host.layoutSubtreeIfNeeded()

        let cellAfter = try #require(table.view(atColumn: 0, row: 0, makeIfNecessary: false))
        let hostViewsAfter = OffscreenHost.allSubviews(of: host)
            .compactMap { $0 as? RowInteractionHost.HostView }
            .map(ObjectIdentifier.init)
        #expect(cellAfter === cellBefore, "同 id 的内容变化触发了整表重建")
        #expect(hostViewsAfter == hostViewsBefore, "行宿主被重建了，正在按住的手势会断")
    }
}
