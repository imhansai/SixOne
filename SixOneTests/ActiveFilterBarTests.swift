//
//  ActiveFilterBarTests.swift
//  SixOneTests
//  活跃筛选条装配：无条件时不占位，有条件时横向滚动、滚轮可横移。
//

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("活跃筛选条装配")
@MainActor
struct ActiveFilterBarTests {
    @Test("没有生效条件时不占位")
    func hidesWithoutFilters() async throws {
        let fixture = try await makeHost(filter: .none)
        defer { fixture.window.orderOut(nil) }
        fixture.host.layoutSubtreeIfNeeded()

        await Wait.settle(milliseconds: 100)
        #expect(
            OffscreenHost.findScrollView(in: fixture.host) == nil,
            "没有筛选条件时不该出现筛选条"
        )
    }

    @Test("有条件时出现横向滚动区域，两端让出面板边距")
    func showsScrollViewWithFilters() async throws {
        let fixture = try await makeHost(
            filter: HistoryFilter(kinds: [.text, .image], dateRanges: [.today])
        )
        defer { fixture.window.orderOut(nil) }
        fixture.host.layoutSubtreeIfNeeded()

        let scrollView = try #require(
            await OffscreenHost.waitForScrollView(in: fixture.host),
            "有筛选条件时没有建出横向滚动区域"
        )
        let frame = scrollView.convert(scrollView.bounds, to: fixture.host)
        let inset = ClipboardLayout.headerHorizontalInset
        #expect(
            abs(frame.minX - inset) < ClipboardLayout.geometryTolerance,
            "滚动区域左侧没有留白"
        )
        #expect(
            frame.maxX
                <= fixture.host.bounds.width - inset + ClipboardLayout.geometryTolerance,
            "滚动区域右侧没有让出按钮位"
        )
    }

    @Test("纵向滚轮把筛选条横向滚动")
    func verticalWheelScrollsFilterBar() async throws {
        let manySources = (0..<12).map { "com.example.application\($0)" }
        let filter = HistoryFilter(
            kinds: Set(ClipboardItemKind.allCases),
            sourceApps: Set(manySources),
            dateRanges: [.today]
        )
        let fixture = try await makeHost(filter: filter)
        defer { fixture.window.orderOut(nil) }
        fixture.host.layoutSubtreeIfNeeded()

        let scrollView = try #require(
            await OffscreenHost.waitForScrollView(in: fixture.host),
            "有筛选条件时没有建出横向滚动区域"
        )
        let bridge = try bridge(in: fixture.host)
        #expect(bridge.enclosingScrollView === scrollView, "滚轮桥不在横向滚动视图里")
        #expect(bridge.isMonitoringEvents, "滚轮桥没有挂上窗口级滚轮监听")
        #expect(bridge.hitTest(NSPoint(x: 1, y: 1)) == nil, "滚轮桥挡住了 chip 的点击")

        let clipView = scrollView.contentView
        let scrollable = await Wait.until {
            (scrollView.documentView?.frame.width ?? 0) > clipView.bounds.width
        }
        #expect(scrollable, "条件不够多，筛选条没有横向溢出")

        #expect(bridge.scrollHorizontally(
            in: scrollView,
            verticalDelta: -1,
            horizontalDelta: 0,
            isPrecise: false
        ))
        let maxOffset = (scrollView.documentView?.frame.width ?? 0) - clipView.bounds.width
        let expectedOffset = min(scrollView.horizontalLineScroll * 3, maxOffset)
        #expect(expectedOffset > 0, "滚轮步长不该为 0")
        #expect(
            await Wait.until {
                abs(clipView.bounds.origin.x - expectedOffset)
                    < ClipboardLayout.geometryTolerance
            },
            "滚轮向下没有把内容向左挪"
        )

        // 滚回最左端。
        #expect(bridge.scrollHorizontally(
            in: scrollView,
            verticalDelta: 1,
            horizontalDelta: 0,
            isPrecise: false
        ))
        #expect(
            await Wait.until {
                abs(clipView.bounds.origin.x) < ClipboardLayout.geometryTolerance
            },
            "滚轮向上没有回到最左端"
        )

        // 触控板的精确增量按点 1:1 移动。
        #expect(bridge.scrollHorizontally(
            in: scrollView,
            verticalDelta: -20,
            horizontalDelta: 0,
            isPrecise: true
        ))
        #expect(
            await Wait.until {
                abs(clipView.bounds.origin.x - 20) < ClipboardLayout.geometryTolerance
            },
            "精确增量没有按点挪动"
        )

        // 触控板左右滑保持系统处理，桥不接管。
        #expect(
            !bridge.scrollHorizontally(
                in: scrollView,
                verticalDelta: 0,
                horizontalDelta: -20,
                isPrecise: true
            ),
            "横向手势不该被滚轮桥吃掉"
        )
        #expect(abs(clipView.bounds.origin.x - 20) < ClipboardLayout.geometryTolerance)
    }

    @Test("超长筛选值被截断，筛选条不会无限变宽")
    func longFilterTitlesAreCapped() async throws {
        let longSources = (0..<4).map { index in
            "com.example." + String(repeating: "verylongsource", count: 4) + "\(index)"
        }
        let fixture = try await makeHost(filter: HistoryFilter(sourceApps: Set(longSources)))
        defer { fixture.window.orderOut(nil) }
        fixture.host.layoutSubtreeIfNeeded()

        let scrollView = try #require(
            await OffscreenHost.waitForScrollView(in: fixture.host),
            "有筛选条件时没有建出横向滚动区域"
        )
        let documentWidth = scrollView.documentView?.frame.width ?? 0
        #expect(
            documentWidth < 1200,
            "超长筛选值把文档撑到 \(documentWidth)pt，文本宽度上限没有生效"
        )
    }

    @Test("预览时把滚轮还给预览，不接管筛选条")
    func wheelBridgeDefersToPreview() async throws {
        let fixture = try await makeHost(filter: HistoryFilter(kinds: [.text, .image]))
        defer { fixture.window.orderOut(nil) }
        fixture.host.layoutSubtreeIfNeeded()

        let bridge = try bridge(in: fixture.host)
        #expect(bridge.isEnabled)

        fixture.context.previewState.item = ClipboardItem(kind: .text, text: "预览")
        #expect(
            await Wait.until { !bridge.isEnabled },
            "预览态下滚轮桥不该继续接管筛选条的滚轮"
        )

        fixture.context.previewState.item = nil
        #expect(
            await Wait.until { bridge.isEnabled },
            "回到列表态后滚轮桥应恢复"
        )
    }

    private struct Fixture {
        let host: NSHostingView<AnyView>
        let window: NSWindow
        let context: PanelContext
    }

    private func bridge(in host: NSView) throws -> HorizontalScrollBridge.BridgeView {
        try #require(
            OffscreenHost.allSubviews(of: host)
                .compactMap { $0 as? HorizontalScrollBridge.BridgeView }
                .first,
            "筛选条没有装上滚轮桥"
        )
    }

    private func makeHost(filter: HistoryFilter) async throws -> Fixture {
        let repository = FakeHistoryRepository()
        let events = ClipboardHistoryEventBus()
        let collections = CollectionListStore(repository: repository, events: events)
        await collections.waitForPendingLoad()

        let context = try TestPanel.context(repository: repository, collections: collections)
        context.store.setFilter(filter)

        let view = AnyView(
            ActiveFilterBar(context: context)
                .environment(context)
                .environment(\.locale, RuntimeLanguage.shared.locale)
                .frame(width: ClipboardLayout.panelWidth)
        )
        let (host, window) = OffscreenHost.make(
            view,
            size: NSSize(
                width: ClipboardLayout.panelWidth,
                height: ClipboardLayout.filterBarHeight
            )
        )
        return Fixture(host: host, window: window, context: context)
    }
}
