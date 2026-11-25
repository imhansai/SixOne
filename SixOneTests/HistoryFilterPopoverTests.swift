//
//  HistoryFilterPopoverTests.swift
//  SixOneTests
//  筛选弹层内容装配：三列固定宽，超过高度上限后在弹层内滚动。
//

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("筛选来源折叠")
struct FilterSourceListLayoutTests {
    private let sources = (0..<10).map { "com.example.app\($0)" }

    @Test("折叠时只露前八个，展开后全量")
    func collapsesToLimit() {
        #expect(
            FilterSourceListLayout.visibleSources(sources, selected: [], isExpanded: false)
                == Array(sources.prefix(8))
        )
        #expect(
            FilterSourceListLayout.visibleSources(sources, selected: [], isExpanded: true)
                == sources
        )
        #expect(FilterSourceListLayout.hasMore(sources, selected: [], isExpanded: false))
        #expect(!FilterSourceListLayout.hasMore(sources, selected: [], isExpanded: true))
    }

    @Test("已选来源排在折叠范围外也保持可见")
    func keepsSelectedVisible() {
        let selected: Set<String> = ["com.example.app8", "com.example.app9"]
        let visible = FilterSourceListLayout.visibleSources(
            sources,
            selected: selected,
            isExpanded: false
        )
        #expect(Array(visible.prefix(8)) == Array(sources.prefix(8)))
        #expect(visible.contains("com.example.app8"))
        #expect(visible.contains("com.example.app9"))
    }

    @Test("来源不超过上限时不折叠")
    func noOverflow() {
        let few = Array(sources.prefix(8))
        #expect(
            FilterSourceListLayout.visibleSources(few, selected: [], isExpanded: false) == few
        )
        #expect(!FilterSourceListLayout.hasMore(few, selected: [], isExpanded: false))
    }

    @Test("已选来源不在最近窗口里时保留候选，保证能取消")
    func keepsSelectedMissingFromCatalog() {
        let catalog = Array(sources.prefix(2))
        #expect(
            FilterSourceListLayout.candidates(
                catalog: catalog,
                selected: ["com.example.gone"]
            ) == catalog + ["com.example.gone"]
        )
        #expect(
            FilterSourceListLayout.candidates(
                catalog: catalog,
                selected: [sources[0]]
            ) == catalog
        )
    }
}

@Suite("筛选弹层装配")
@MainActor
struct HistoryFilterPopoverTests {
    @Test("内容放进有高度上限的滚动区")
    func usesCappedScrollContent() async throws {
        let fixture = try await makeHost(
            groups: ["Work", "Personal"],
            sources: ["com.apple.Safari", "com.apple.Notes"]
        )
        defer { fixture.window.orderOut(nil) }
        fixture.host.layoutSubtreeIfNeeded()
        await Wait.settle(milliseconds: 100)

        #expect(
            OffscreenHost.findScrollView(in: fixture.host) != nil,
            "弹层内容应放进滚动区"
        )
        #expect(fixture.host.fittingSize.width > 0)
        #expect(
            fixture.host.fittingSize.height
                <= HistoryFilterPopover.maximumContentHeight + ClipboardLayout.geometryTolerance,
            "内容没有受高度上限约束：\(fixture.host.fittingSize.height)"
        )
        #expect(fixture.context.store.filter == .none, "渲染弹层不该改动筛选条件")
    }

    @Test("选项多时内容长高到上限后改为滚动")
    func contentGrowsThenScrolls() async throws {
        let short = try await makeHost(
            groups: ["Group 0"],
            sources: ["com.example.app0"]
        )
        defer { short.window.orderOut(nil) }
        short.host.layoutSubtreeIfNeeded()
        await Wait.settle(milliseconds: 100)

        let long = try await makeHost(
            groups: (0..<20).map { "Group \($0)" },
            sources: (0..<18).map { "com.example.app\($0)" }
        )
        defer { long.window.orderOut(nil) }
        long.host.layoutSubtreeIfNeeded()
        await Wait.settle(milliseconds: 100)

        let shortHeight = short.host.fittingSize.height
        let longHeight = long.host.fittingSize.height
        #expect(
            shortHeight < HistoryFilterPopover.maximumContentHeight,
            "短内容不该被上限拉高：\(shortHeight)"
        )
        #expect(
            longHeight
                <= HistoryFilterPopover.maximumContentHeight + ClipboardLayout.geometryTolerance,
            "长内容没有被上限截住：\(longHeight)"
        )
        #expect(longHeight > shortHeight, "内容应随选项增长直到上限")
    }

    private struct Fixture {
        let host: NSHostingView<AnyView>
        let window: NSWindow
        let context: PanelContext
    }

    private func makeHost(groups: [String], sources: [String]) async throws -> Fixture {
        let repository = FakeHistoryRepository()
        await repository.setCollections(groups.map {
            CollectionRow(id: UUID(), name: $0, createdAt: Date())
        })
        await repository.setSourceApplications(sources)
        let collections = CollectionListStore(
            repository: repository,
            events: ClipboardHistoryEventBus()
        )
        await collections.waitForPendingLoad()

        let context = try TestPanel.context(repository: repository, collections: collections)
        // 与真实唤出路径一致：先预热来源，再渲染弹层。
        context.filterSources.reload()
        await context.filterSources.waitForPendingLoad()

        let view = AnyView(
            HistoryFilterPopover(context: context)
                .environment(context)
                .environment(\.locale, RuntimeLanguage.shared.locale)
        )
        let size = NSSize(
            width: ClipboardLayout.panelWidth,
            height: ClipboardLayout.panelHeight
        )
        let (host, window) = OffscreenHost.make(view, size: size)
        return Fixture(host: host, window: window, context: context)
    }
}
