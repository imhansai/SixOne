//
//  CollectionFilterBarTests.swift
//  SixOneTests
//  分组筛选条装配：有分组时出现横向滚动区域，且两端留出面板边距。
//

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("分组筛选条装配")
@MainActor
struct CollectionFilterBarTests {
    @Test("没有分组时不占位")
    func hidesWithoutGroups() async throws {
        let fixture = try await makeHost(groups: [])
        defer { fixture.window.orderOut(nil) }
        fixture.host.layoutSubtreeIfNeeded()

        await Wait.settle(milliseconds: 100)
        #expect(
            OffscreenHost.findScrollView(in: fixture.host) == nil,
            "没有分组时不该出现筛选条"
        )
    }

    @Test("横向滚动区域两端让出面板边距")
    func scrollViewKeepsHorizontalInset() async throws {
        let fixture = try await makeHost(groups: ["Work", "Personal"])
        defer { fixture.window.orderOut(nil) }
        fixture.host.layoutSubtreeIfNeeded()

        let scrollView = try #require(
            await OffscreenHost.waitForScrollView(in: fixture.host),
            "有分组时没有建出横向滚动区域"
        )
        let frame = scrollView.convert(scrollView.bounds, to: fixture.host)
        let inset = ClipboardLayout.headerHorizontalInset
        #expect(
            abs(frame.minX - inset) < ClipboardLayout.geometryTolerance,
            "滚动区域左侧没有留白"
        )
        #expect(
            abs(frame.maxX - (fixture.host.bounds.width - inset)) < ClipboardLayout.geometryTolerance,
            "滚动区域右侧没有留白"
        )
    }

    @Test("纵向滚轮把筛选条横向滚动")
    func verticalWheelScrollsFilterBar() async throws {
        let fixture = try await makeHost(groups: (0..<12).map { "Group \($0)" })
        defer { fixture.window.orderOut(nil) }
        fixture.host.layoutSubtreeIfNeeded()

        let scrollView = try #require(
            await OffscreenHost.waitForScrollView(in: fixture.host),
            "有分组时没有建出横向滚动区域"
        )
        let bridge = try bridge(in: fixture.host)
        #expect(bridge.enclosingScrollView === scrollView, "滚轮桥不在横向滚动视图里")
        #expect(bridge.isMonitoringEvents, "滚轮桥没有挂上窗口级滚轮监听")
        #expect(bridge.hitTest(NSPoint(x: 1, y: 1)) == nil, "滚轮桥挡住了 chip 的点击")

        let clipView = scrollView.contentView
        let scrollable = await Wait.until {
            (scrollView.documentView?.frame.width ?? 0) > clipView.bounds.width
        }
        #expect(scrollable, "分组不够多，筛选条没有横向溢出")

        // 鼠标滚轮一格（非精确增量）按三行横向移动。
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

    @Test("预览时把滚轮还给预览，不接管筛选条")
    func wheelBridgeDefersToPreview() async throws {
        let fixture = try await makeHost(groups: ["Work", "Personal"])
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

    @Test("超长分组名被截断，筛选条不会无限变宽")
    func longGroupNamesAreCapped() async throws {
        let longNames = (0..<4).map { index in
            String(repeating: "超长分组名", count: 8) + "\(index)"
        }
        let fixture = try await makeHost(groups: longNames)
        defer { fixture.window.orderOut(nil) }
        fixture.host.layoutSubtreeIfNeeded()

        let scrollView = try #require(
            await OffscreenHost.waitForScrollView(in: fixture.host),
            "有分组时没有建出横向滚动区域"
        )
        let clipWidth = scrollView.contentView.bounds.width
        let overflowed = await Wait.until {
            (scrollView.documentView?.frame.width ?? 0) > clipWidth
        }
        #expect(overflowed, "前置现场不对：四个超长分组没有横向溢出")

        let documentWidth = scrollView.documentView?.frame.width ?? 0
        #expect(
            documentWidth < 900,
            "超长分组名把文档撑到 \(documentWidth)pt，文本宽度上限没有生效"
        )
    }

    @Test("新增分组后筛选条移动到底，完整露出新分组")
    func appendingGroupScrollsToEnd() async throws {
        let fixture = try await makeHost(groups: (0..<12).map { "Group \($0)" })
        defer { fixture.window.orderOut(nil) }
        fixture.host.layoutSubtreeIfNeeded()

        let scrollView = try #require(
            await OffscreenHost.waitForScrollView(in: fixture.host),
            "有分组时没有建出横向滚动区域"
        )
        let clipView = scrollView.contentView
        let scrollable = await Wait.until {
            (scrollView.documentView?.frame.width ?? 0) > clipView.bounds.width
        }
        #expect(scrollable, "分组不够多，筛选条没有横向溢出")
        #expect(abs(clipView.bounds.origin.x) < ClipboardLayout.geometryTolerance)

        // 模拟新建分组：库列表末尾追加一条并广播分组变化。
        var rows = fixture.collections.groups
        let newGroup = CollectionRow(id: UUID(), name: "Newest", createdAt: Date())
        rows.append(newGroup)
        await fixture.repository.setCollections(rows)
        fixture.events.post(.collectionsChanged)
        await fixture.collections.waitForPendingLoad()
        #expect(fixture.collections.groups.last?.id == newGroup.id)

        let revealed = await Wait.until {
            guard let documentView = scrollView.documentView else { return false }
            let maxOffset = max(0, documentView.frame.width - clipView.bounds.width)
            return maxOffset > 0
                && abs(clipView.bounds.origin.x - maxOffset) < ClipboardLayout.geometryTolerance
        }
        let finalOffset = clipView.bounds.origin.x
        let finalMax = max(0, (scrollView.documentView?.frame.width ?? 0) - clipView.bounds.width)
        #expect(
            revealed,
            "新增分组后筛选条没有移动到底：offset=\(finalOffset) max=\(finalMax) groups=\(fixture.collections.groups.count)"
        )
    }

    private struct Fixture {
        let host: NSHostingView<AnyView>
        let window: NSWindow
        let context: PanelContext
        let repository: FakeHistoryRepository
        let events: ClipboardHistoryEventBus
        let collections: CollectionListStore
    }

    private func bridge(in host: NSView) throws -> HorizontalScrollBridge.BridgeView {
        try #require(
            OffscreenHost.allSubviews(of: host)
                .compactMap { $0 as? HorizontalScrollBridge.BridgeView }
                .first,
            "筛选条没有装上滚轮桥"
        )
    }

    private func makeHost(groups: [String]) async throws -> Fixture {
        let repository = FakeHistoryRepository()
        await repository.setCollections(groups.map {
            CollectionRow(id: UUID(), name: $0, createdAt: Date())
        })
        let events = ClipboardHistoryEventBus()
        let collections = CollectionListStore(
            repository: repository,
            events: events
        )
        await collections.waitForPendingLoad()

        let context = try TestPanel.context(repository: repository, collections: collections)
        let view = AnyView(
            CollectionFilterBar(context: context)
                .environment(context)
                .environment(\.locale, RuntimeLanguage.shared.locale)
                .frame(width: ClipboardLayout.panelWidth)
        )
        let (host, window) = OffscreenHost.make(
            view,
            size: NSSize(
                width: ClipboardLayout.panelWidth,
                height: ClipboardLayout.collectionFilterBarHeight
            )
        )
        return Fixture(
            host: host,
            window: window,
            context: context,
            repository: repository,
            events: events,
            collections: collections
        )
    }
}
