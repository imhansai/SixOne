//
//  HistoryListScrollTests.swift
//  SixOneTests
//  远跳后视口无空条；滚动目标按 id 解析；滚进视野带留白。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("列表远跳定位")
@MainActor
struct HistoryListScrollTests {
    private static let rowCount = 200
    private static let viewportSize = NSSize(width: ClipboardLayout.panelWidth, height: 491)

    private func makeView(
        _ context: PanelContext,
        rows: [HistoryRow],
        dataRevision: Int = 0,
        selectedItemID: UUID? = nil,
        target: HistoryListScrollTarget?
    ) -> AnyView {
        if let target {
            switch target {
            case .row(let id):
                context.navigationState.requestScroll(toRow: id)
            case .top:
                context.navigationState.requestScrollToTop()
            }
        }
        return AnyView(
            HistoryListTableView(
                context: context,
                rows: rows,
                dataRevision: dataRevision,
                locale: Locale(identifier: "en"),
                selectedItemID: selectedItemID,
                scrollRevision: context.navigationState.scrollRevision,
                onSelect: { _ in },
                onActivate: { _, _ in },
                onCopy: { _ in },
                menuProvider: { _, _ in nil }
            )
        )
    }

    private func assertNoBlankRegion(
        _ scrollView: NSScrollView,
        _ tableView: NSTableView,
        targetRow: Int,
        comment: Comment
    ) {
        let visible = scrollView.documentVisibleRect
        #expect(visible.contains(tableView.rect(ofRow: targetRow)), comment)
        let rows = tableView.rows(in: visible)
        #expect(rows.length > 0, "视口里一行都没有 —— 那一片就是空白")
        for row in rows.location..<(rows.location + rows.length) {
            #expect(
                tableView.view(atColumn: 0, row: row, makeIfNecessary: false) != nil,
                "第 \(row) 行落在视野里却没有实例化"
            )
        }
    }

    @Test("滚动几何：已可见不动，越界最小滚动，两端钳在文档边界")
    func scrollGeometryClampsAtDocumentEdges() {
        let visible = CGRect(x: 0, y: 100, width: 100, height: 400)

        #expect(HistoryListScrollGeometry.targetOriginY(
            paddedRow: CGRect(x: 0, y: 150, width: 100, height: 100),
            visible: visible,
            documentHeight: 600
        ) == 100, "整行已可见就不该动")

        #expect(HistoryListScrollGeometry.targetOriginY(
            paddedRow: CGRect(x: 0, y: 480, width: 100, height: 100),
            visible: visible,
            documentHeight: 600
        ) == 180, "下边缘越界：只滚到刚好露出留白")

        #expect(HistoryListScrollGeometry.targetOriginY(
            paddedRow: CGRect(x: 0, y: 20, width: 100, height: 50),
            visible: visible,
            documentHeight: 600
        ) == 20, "上边缘越界：只滚到行顶")

        #expect(HistoryListScrollGeometry.targetOriginY(
            paddedRow: CGRect(x: 0, y: -8, width: 100, height: 50),
            visible: visible,
            documentHeight: 600
        ) == 0, "文档顶部不能滚成负数")

        #expect(HistoryListScrollGeometry.targetOriginY(
            paddedRow: CGRect(x: 0, y: 550, width: 100, height: 100),
            visible: visible,
            documentHeight: 600
        ) == 200, "文档底部不能滚过 maxY")
    }

    @Test("⌘↓ 跳到窗口最旧一条：同一轮里落点行就位，视口没有空条")
    func jumpToOldestKeepsViewportFilled() async throws {
        let context = try TestPanel.context()
        let rows = (0..<Self.rowCount).map { HistoryRow.stub(title: "第 \($0) 行") }
        let (host, window) = OffscreenHost.make(makeView(context, rows: rows, target: nil), size: Self.viewportSize)
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)

        host.rootView = makeView(context, rows: rows, target: .row(rows[rows.count - 1].id))
        // 不额外等待，本轮 SwiftUI 更新后即须成立。
        host.layoutSubtreeIfNeeded()

        assertNoBlankRegion(
            scrollView,
            tableView,
            targetRow: rows.count - 1,
            comment: "⌘↓ 之后落点行不在视野里"
        )
    }

    @Test("⌘↑ 跳回第一条：同一轮里落点行就位，视口没有空条")
    func jumpToFirstKeepsViewportFilled() async throws {
        let context = try TestPanel.context()
        let rows = (0..<Self.rowCount).map { HistoryRow.stub(title: "第 \($0) 行") }
        let (host, window) = OffscreenHost.make(makeView(context, rows: rows, target: nil), size: Self.viewportSize)
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)

        host.rootView = makeView(context, rows: rows, target: .row(rows[rows.count - 1].id))
        host.layoutSubtreeIfNeeded()
        host.rootView = makeView(context, rows: rows, target: .row(rows[0].id))
        host.layoutSubtreeIfNeeded()

        assertNoBlankRegion(scrollView, tableView, targetRow: 0, comment: "⌘↑ 之后落点行不在视野里")
    }

    @Test("滚动目标按 id 解析，不依赖请求发出时的行号")
    func scrollTargetResolvesByIdentity() async throws {
        let context = try TestPanel.context()
        let rows = (0..<60).map { HistoryRow.stub(title: "第 \($0) 行") }
        let target = rows[10]
        let (host, window) = OffscreenHost.make(makeView(context, rows: rows, target: nil), size: Self.viewportSize)
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)

        let reordered = Array(rows[30...]) + Array(rows[..<30])
        host.rootView = makeView(
            context,
            rows: reordered,
            dataRevision: 1,
            target: .row(target.id)
        )
        host.layoutSubtreeIfNeeded()

        #expect(scrollView.documentVisibleRect.contains(tableView.rect(ofRow: 40)), "没有滚到目标 id 的新行号")
    }

    @Test("目标 id 已不在列表里时不滚动")
    func missingScrollTargetIsIgnored() async throws {
        let context = try TestPanel.context()
        let rows = (0..<60).map { HistoryRow.stub(title: "第 \($0) 行") }
        let (host, window) = OffscreenHost.make(makeView(context, rows: rows, target: nil), size: Self.viewportSize)
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let before = scrollView.documentVisibleRect.origin

        host.rootView = makeView(context, rows: rows, target: .row(UUID()))
        host.layoutSubtreeIfNeeded()

        #expect(scrollView.documentVisibleRect.origin == before)
    }

    /// 真实行渲染兜底：每行宿主是独立 SwiftUI 树，漏注入环境会崩。
    @Test("真实历史行挂进表格：环境注入到位，行交互宿主存在")
    func hostsRealRowInsideTableCell() async throws {
        let context = try TestPanel.context()
        let rows = [HistoryRow.stub(title: "唯一的一行")]
        let (host, window) = OffscreenHost.make(makeView(context, rows: rows, target: nil), size: Self.viewportSize)
        defer { window.orderOut(nil) }

        let interactionHosts = await waitForInteractionHosts(in: host)
        #expect(!interactionHosts.isEmpty, "行没有渲染进表格单元格")
        #expect(interactionHosts.contains { $0.bounds.width > 100 }, "整行没有交互宿主，单击选不中")
    }

    @Test("表格选中跟着模型的选中走，模型清了它也清")
    func mirrorsSelectionOneWay() async throws {
        let context = try TestPanel.context()
        let rows = (0..<40).map { HistoryRow.stub(title: "第 \($0) 行") }
        let (host, window) = OffscreenHost.make(makeView(context, rows: rows, target: nil), size: Self.viewportSize)
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(tableView.selectedRow == -1, "还没选中时表格不该有选中行")

        host.rootView = makeView(
            context,
            rows: rows,
            selectedItemID: rows[5].id,
            target: nil
        )
        await Wait.until { tableView.selectedRow == 5 }
        #expect(tableView.selectedRow == 5, "表格没有跟着模型选中第 5 行")

        host.rootView = makeView(context, rows: rows, target: nil)
        await Wait.until { tableView.selectedRow == -1 }
        #expect(tableView.selectedRow == -1, "模型清了选中，表格还留着")
    }

    @Test("被切掉的行滚进视野后，与视口边缘之间留出留白")
    func revealedRowKeepsBreathingRoom() async throws {
        let context = try TestPanel.context()
        let rows = (0..<200).map { HistoryRow.stub(title: "第 \($0) 行") }
        let (host, window) = OffscreenHost.make(makeView(context, rows: rows, target: nil), size: Self.viewportSize)
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)
        let clipHeight = scrollView.contentView.bounds.height

        let row20 = tableView.rect(ofRow: 20)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: row20.minY + 20))
        host.rootView = makeView(context, rows: rows, target: .row(rows[20].id))
        await Wait.until {
            abs(tableView.rect(ofRow: 20).minY - scrollView.documentVisibleRect.minY
                - ClipboardLayout.verticalPadding) < 0.5
        }
        #expect(
            abs(tableView.rect(ofRow: 20).minY - scrollView.documentVisibleRect.minY
                - ClipboardLayout.verticalPadding) < 0.5,
            "顶部没有留出边距"
        )

        let row21 = tableView.rect(ofRow: 21)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: row21.minY + 20 - clipHeight))
        host.rootView = makeView(context, rows: rows, target: .row(rows[21].id))
        await Wait.until {
            abs(scrollView.documentVisibleRect.maxY - tableView.rect(ofRow: 21).maxY
                - ClipboardLayout.verticalPadding) < 0.5
        }
        #expect(
            abs(scrollView.documentVisibleRect.maxY - tableView.rect(ofRow: 21).maxY
                - ClipboardLayout.verticalPadding) < 0.5,
            "底部留出的边距不对"
        )
    }

    @Test("点一条贴着视口边缘的完整行，也会补出留白")
    func clickingFlushRowRestoresBreathingRoom() async throws {
        let context = try TestPanel.context()
        let rows = (0..<200).map { HistoryRow.stub(title: "第 \($0) 行") }
        let (host, window) = OffscreenHost.make(makeView(context, rows: rows, target: nil), size: Self.viewportSize)
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)

        let row20 = tableView.rect(ofRow: 20)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: row20.minY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        #expect(scrollView.documentVisibleRect.contains(row20), "用例没把目标行摆成完整可见")

        host.rootView = makeView(context, rows: rows, target: .row(rows[20].id))
        await Wait.until {
            abs(tableView.rect(ofRow: 20).minY - scrollView.documentVisibleRect.minY
                - ClipboardLayout.verticalPadding) < 0.5
        }
        #expect(
            abs(tableView.rect(ofRow: 20).minY - scrollView.documentVisibleRect.minY
                - ClipboardLayout.verticalPadding) < 0.5,
            "贴着边的完整行没有补出留白"
        )

        let origin = scrollView.contentView.bounds.origin
        host.rootView = makeView(context, rows: rows, target: .row(rows[20].id))
        await Wait.settle(milliseconds: 80)
        #expect(scrollView.contentView.bounds.origin == origin, "已经有留白，点击却动了列表")
    }

    /// 轮询到行宿主出现，固定睡眠在并行跑时不够。
    private func waitForInteractionHosts(in host: NSView) async -> [RowInteractionHost.HostView] {
        var found: [RowInteractionHost.HostView] = []
        await Wait.until {
            found = OffscreenHost.allSubviews(of: host).compactMap { $0 as? RowInteractionHost.HostView }
            return !found.isEmpty
        }
        return found
    }
}
