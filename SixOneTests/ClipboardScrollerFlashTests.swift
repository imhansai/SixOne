//
//  ClipboardScrollerFlashTests.swift
//  SixOneTests
//  滚动条反馈：程序化滚动调用 `flashScrollers()`；无位移的端点跳转不点亮滚动条。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@MainActor
private final class BeepCounter {
    var count = 0
}

/// 用例改写进程级 `flashScrollers`，故串行跑。
@Suite("列表滚动条反馈", .serialized)
@MainActor
struct ClipboardScrollerFlashTests {
    private static let viewportSize = NSSize(width: 640, height: 491)
    private static let rowCount = 200

    private func rows(_ count: Int = ClipboardScrollerFlashTests.rowCount) -> [HistoryRow] {
        (0..<count).map { HistoryRow.stub(title: "第 \($0) 行") }
    }

    private func makeView(
        _ context: PanelContext,
        rows: [HistoryRow],
        dataRevision: Int = 0,
        target: HistoryListScrollTarget?,
        isEndpointJump: Bool = false,
        isSelectionAlreadyAtEndpoint: Bool = false,
        beep: @escaping () -> Void = {}
    ) -> AnyView {
        if let target {
            switch target {
            case .row(let id):
                context.navigationState.requestScroll(
                    toRow: id,
                    isEndpointJump: isEndpointJump,
                    isSelectionAlreadyAtEndpoint: isSelectionAlreadyAtEndpoint
                )
            case .top:
                context.navigationState.requestScrollToTop(isEndpointJump: isEndpointJump)
            }
        }
        return AnyView(
            HistoryListTableView(
                context: context,
                rows: rows,
                dataRevision: dataRevision,
                locale: Locale(identifier: "en"),
                selectedItemID: nil,
                scrollRevision: context.navigationState.scrollRevision,
                onSelect: { _ in },
                onActivate: { _, _ in },
                onCopy: { _ in },
                menuProvider: { _, _ in nil },
                beep: beep
            )
        )
    }

    /// 读 AppKit 私有 imp 状态判断显隐，仅测试使用。
    private func knobAlpha(_ scrollView: NSScrollView) -> Double {
        guard let scroller = scrollView.verticalScroller,
              let imp = scroller.value(forKey: "scrollerImp") as? NSObject,
              let number = imp.value(forKey: "knobAlpha") as? NSNumber else { return -1 }
        return number.doubleValue
    }

    /// 固定浮层滚动条，避免传统样式常亮；只改测试视图，不动用户偏好。
    private func forceOverlayScroller(_ scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
    }

    @Test("列表使用关闭滚动动画的 clip view")
    func usesAnimationDisabledClipView() async throws {
        let context = try TestPanel.context()
        let rows = rows()
        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, target: nil),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        #expect(scrollView.contentView is ListClipView, "列表没有使用关闭动画的 clip view")
    }

    @Test("程序化滚动每一步都调用官方 flashScrollers")
    func flashesSystemScrollersOnProgrammaticScroll() async throws {
        ScrollerFlashProbe.install()
        defer { ScrollerFlashProbe.uninstall() }
        let context = try TestPanel.context()
        let rows = rows()

        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, target: nil),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == rows.count }, "行没有落进表格")
        let before = ScrollerFlashProbe.count(for: scrollView)

        host.rootView = makeView(context, rows: rows, target: .row(rows[20].id))
        let scrolled = await Wait.until { OffscreenHost.offsetFromTop(scrollView) > 0 }
        #expect(scrolled, "目标行没有滚进视野，用例没走到真实路径")
        #expect(
            ScrollerFlashProbe.count(for: scrollView) > before,
            "程序化滚动没有调用 flashScrollers，系统滚动条会按 0.5s 计时器淡出"
        )
    }

    @Test("滚动块位置跟着视口走")
    func scrollerTracksViewport() async throws {
        let context = try TestPanel.context()
        let rows = rows()
        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, target: nil),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)
        let scroller = try #require(scrollView.verticalScroller)
        #expect(await Wait.until { tableView.numberOfRows == rows.count }, "行没有落进表格")
        #expect(abs(scroller.doubleValue) < 0.001, "顶部时滚动块应停在轨道起点")

        host.rootView = makeView(context, rows: rows, target: .row(rows[20].id))
        #expect(await Wait.until { OffscreenHost.offsetFromTop(scrollView) > 0 }, "目标行没有滚进视野")
        #expect(scroller.doubleValue > 0.001, "滚动块没有跟着视口移动")
        #expect(scroller.knobProportion < 1, "滚动块比例应小于 1")

        host.rootView = makeView(context, rows: rows, target: .top)
        #expect(await Wait.until { OffscreenHost.offsetFromTop(scrollView) == 0 }, "没有回到顶部")
        #expect(abs(scroller.doubleValue) < 0.001, "回到顶部后滚动块没有回到轨道起点")
    }

    @Test("文档变短时滚动块比例跟着更新")
    func knobProportionTracksDocumentHeight() async throws {
        let context = try TestPanel.context()
        let rows = rows()
        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, target: nil),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == rows.count }, "行没有落进表格")
        let scroller = try #require(scrollView.verticalScroller)
        let proportionBefore = scroller.knobProportion
        #expect(proportionBefore > 0, "用例前提：滚动块比例应大于 0")

        host.rootView = makeView(
            context,
            rows: Array(rows.prefix(20)),
            dataRevision: 1,
            target: nil
        )
        let shrank = await Wait.until { scroller.knobProportion > proportionBefore }
        #expect(shrank, "文档变短后滚动块比例没有变长")
    }

    @Test("滚动条在最后一次滚动后自动淡出")
    func scrollerFadesAfterLastScroll() async throws {
        let context = try TestPanel.context()
        let rows = rows()
        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, target: nil),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == rows.count }, "行没有落进表格")
        forceOverlayScroller(scrollView)

        host.rootView = makeView(context, rows: rows, target: .row(rows[20].id))
        #expect(await Wait.until { knobAlpha(scrollView) > 0.5 }, "滚动后滚动条没有出现")
        let faded = await Wait.until(timeout: .seconds(2)) { knobAlpha(scrollView) < 0.1 }
        #expect(faded, "最后一次滚动之后滚动条没有淡出")
    }

    @Test("滚到首尾两端都不会越界")
    func scrollStopsAtDocumentEdges() async throws {
        let context = try TestPanel.context()
        let rows = rows()

        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, target: nil),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == rows.count }, "行没有落进表格")

        host.rootView = makeView(context, rows: rows, target: .row(rows[rows.count - 1].id))
        let reachedBottom = await Wait.until {
            scrollView.documentVisibleRect.contains(tableView.rect(ofRow: rows.count - 1))
        }
        #expect(reachedBottom, "最后一条没有完整滚进视野")
        #expect(OffscreenHost.offsetFromTop(scrollView) == maxOffset(of: scrollView), "没有停在文档下边缘")

        host.rootView = makeView(context, rows: rows, target: .top)
        let reachedTop = await Wait.until {
            scrollView.documentVisibleRect.contains(tableView.rect(ofRow: 0))
        }
        #expect(reachedTop, "第一条没有完整滚进视野")
        #expect(OffscreenHost.offsetFromTop(scrollView) == minOffset(of: scrollView), "没有停在文档上边缘")
    }

    @Test("滚动范围止于内容两端，不留可停留的空带")
    func scrollRangeStopsAtContentEdges() async throws {
        let context = try TestPanel.context()
        let rows = rows()
        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, target: nil),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == rows.count }, "行没有落进表格")
        let documentHeight = try #require(scrollView.documentView?.frame.height)
        #expect(
            documentHeight == CGFloat(rows.count) * ClipboardLayout.rowHeight + ClipboardLayout.verticalPadding * 2,
            "文档高度没有把上下留白算进去"
        )
        #expect(minOffset(of: scrollView) == 0, "列表上方还能停到内容之外：那一条点不到任何行")
        #expect(
            maxOffset(of: scrollView) == documentHeight - scrollView.contentView.bounds.height,
            "列表下方还能停到内容之外：那一条点不到任何行"
        )
    }

    private func maxOffset(of scrollView: NSScrollView) -> CGFloat {
        constrainedOrigin(scrollView, y: 1_000_000).y
    }

    private func minOffset(of scrollView: NSScrollView) -> CGFloat {
        constrainedOrigin(scrollView, y: -1_000_000).y
    }

    private func constrainedOrigin(_ scrollView: NSScrollView, y: CGFloat) -> CGPoint {
        let clip = scrollView.contentView
        return clip.constrainBoundsRect(
            NSRect(origin: NSPoint(x: 0, y: y), size: clip.bounds.size)
        ).origin
    }

    @Test("端点跳转没有位移时播放提示音，不亮滚动条")
    func endpointJumpWithoutMovementBeeps() async throws {
        let context = try TestPanel.context()
        let rows = rows()
        let counter = BeepCounter()
        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, target: nil, beep: { counter.count += 1 }),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == rows.count }, "行没有落进表格")
        forceOverlayScroller(scrollView)
        #expect(OffscreenHost.offsetFromTop(scrollView) == 0)
        await Wait.settle(milliseconds: 1500)
        #expect(knobAlpha(scrollView) < 0.5, "用例前提：滚动条应该已经淡出")

        host.rootView = makeView(
            context,
            rows: rows,
            target: .row(rows[0].id),
            isEndpointJump: true,
            isSelectionAlreadyAtEndpoint: true,
            beep: { counter.count += 1 }
        )
        await Wait.settle(milliseconds: 250)

        #expect(OffscreenHost.offsetFromTop(scrollView) == 0, "端点命令不该把视口移走")
        #expect(knobAlpha(scrollView) < 0.5, "端点空操作不该点亮滚动条")
        #expect(counter.count == 1, "端点空操作应该响一次系统提示音")
    }

    @Test("选中变了但视口已经在端点：没有位移就不闪")
    func selectionChangeWithoutMovementDoesNotFlash() async throws {
        ScrollerFlashProbe.install()
        defer { ScrollerFlashProbe.uninstall() }

        let context = try TestPanel.context()
        let rows = rows()
        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, target: nil),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == rows.count }, "行没有落进表格")
        #expect(OffscreenHost.offsetFromTop(scrollView) == 0, "用例前提：视口应该在顶部")

        let before = ScrollerFlashProbe.count(for: scrollView)

        host.rootView = makeView(
            context,
            rows: rows,
            target: .row(rows[0].id),
            isEndpointJump: true,
            isSelectionAlreadyAtEndpoint: false
        )
        await Wait.settle(milliseconds: 250)

        #expect(OffscreenHost.offsetFromTop(scrollView) == 0, "没有位移却把视口挪走了")
        #expect(
            ScrollerFlashProbe.count(for: scrollView) == before,
            "没有位移却点亮了滚动条"
        )
    }

    @Test("快速交替的端点命令全部入队，最后一次回到顶部时点亮滚动条")
    func rapidAlternatingEndpointCommandsRevealScroller() async throws {
        let context = try TestPanel.context()
        let rows = rows()
        let counter = BeepCounter()
        let (host, window) = OffscreenHost.make(
            makeView(context, rows: rows, target: nil, beep: { counter.count += 1 }),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "没找到滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == rows.count }, "行没有落进表格")
        forceOverlayScroller(scrollView)
        await Wait.settle(milliseconds: 1500)
        #expect(knobAlpha(scrollView) < 0.5, "用例前提：滚动条应该已经淡出")

        context.navigationState.requestScroll(
            toRow: rows[rows.count - 1].id,
            isEndpointJump: true,
            isSelectionAlreadyAtEndpoint: false
        )
        context.navigationState.requestScrollToTop(isEndpointJump: true)

        host.rootView = makeView(
            context,
            rows: rows,
            target: nil,
            beep: { counter.count += 1 }
        )
        // 滚动条显隐是动画，固定延时在并行负载下会抖，故条件等待。
        let revealed = await Wait.until { knobAlpha(scrollView) > 0.5 }

        #expect(OffscreenHost.offsetFromTop(scrollView) == 0, "最终位置应该在顶部")
        #expect(counter.count == 0, "改变过选中的跳转不该响提示音")
        #expect(revealed, "快速交替后滚动条没有亮起来")
    }
}
