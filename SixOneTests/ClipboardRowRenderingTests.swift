//
//  ClipboardRowRenderingTests.swift
//  SixOneTests
//  真实行几何：选中不改行高；复制命中目标与按钮矩形同源。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@MainActor
private func makeRowHost(
    rowCount: Int = 3,
    selectFirstRow: Bool = false,
    topPadding: CGFloat = 0,
    bottomPadding: CGFloat = 0,
    shortcutNumber: Int? = nil
) throws -> (host: NSHostingView<AnyView>, window: NSWindow, context: PanelContext) {
    let harness = try ClipboardHarness()
    let context = PanelContext(
        manager: harness.manager,
        store: HistoryListStore(repository: FakeHistoryRepository(), events: ClipboardHistoryEventBus()),
        caches: PanelCaches()
    )
    let rows = (0..<rowCount).map { index in
        HistoryRow(ClipboardItem(kind: .text, text: "第 \(index) 行"))
    }
    let root = AnyView(
        VStack(spacing: 0) {
            Color.clear.frame(height: ClipboardLayout.verticalPadding)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                ClipboardRowView(
                    row: row,
                    shortcutNumber: shortcutNumber,
                    isSelected: selectFirstRow && index == 0,
                    isListActive: selectFirstRow,
                    listTopPadding: index == 0 ? topPadding : 0,
                    listBottomPadding: index == rows.count - 1 ? bottomPadding : 0,
                    onSelect: { _ in },
                    onActivate: { _, _ in },
                    onCopy: {},
                    menuProvider: { _ in nil }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(context)
    )

    let host = NSHostingView(rootView: root)
    let documentHeight = CGFloat(40) * ClipboardLayout.rowHeight + ClipboardLayout.verticalPadding * 2
    host.frame = NSRect(
        x: 0,
        y: 0,
        width: ClipboardLayout.panelWidth,
        height: documentHeight
    )
    let window = NSWindow(
        contentRect: NSRect(x: -10000, y: -10000, width: host.frame.width, height: 400),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = host
    window.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    return (host, window, context)
}

@MainActor
private func interactionHosts(in host: NSView) -> [(view: RowInteractionHost.HostView, rect: NSRect)] {
    OffscreenHost.allSubviews(of: host)
        .compactMap { $0 as? RowInteractionHost.HostView }
        .map { view in (view, view.convert(view.bounds, to: host)) }
}

@MainActor
private func copyHitTargets(in host: NSView) -> [(view: RowCopyHitTarget.HostView, rect: NSRect)] {
    OffscreenHost.allSubviews(of: host)
        .compactMap { $0 as? RowCopyHitTarget.HostView }
        .map { view in (view, view.convert(view.bounds, to: host)) }
}

@Suite("选中行的高度")
@MainActor
struct RowSelectionLayoutTests {
    private func firstRowHeight(selected: Bool) throws -> CGFloat? {
        let (host, window, _) = try makeRowHost(selectFirstRow: selected)
        defer { window.orderOut(nil) }

        let bodies = interactionHosts(in: host)
            .filter { $0.rect.width > 100 }
            .sorted { $0.rect.midY < $1.rect.midY }
        guard let first = bodies.first else { return nil }
        return (first.rect.midY - ClipboardLayout.verticalPadding) * 2
    }

    @Test("未选中时行高等于 rowHeight")
    func unselectedRowKeepsHeight() throws {
        let height = try #require(try firstRowHeight(selected: false))
        #expect(height == ClipboardLayout.rowHeight)
    }

    @Test("选中一行不会把它撑高")
    func selectedRowKeepsHeight() throws {
        let height = try #require(try firstRowHeight(selected: true))
        #expect(height == ClipboardLayout.rowHeight, "选中的行被高亮撑高了（大片高亮）")
    }

    /// 首行留白须落在点击区内，否则会出现点不动的窄带。
    @Test("首行的列表留白也在交互宿主里")
    func firstRowPaddingIsInsideInteractionHost() throws {
        let (host, window, _) = try makeRowHost(
            rowCount: 1,
            topPadding: ClipboardLayout.verticalPadding
        )
        defer { window.orderOut(nil) }

        let bodies = interactionHosts(in: host)
            .filter { $0.rect.width > 100 }
            .sorted { $0.rect.midY < $1.rect.midY }
        let body = try #require(bodies.first)
        #expect(
            abs(body.rect.minY - ClipboardLayout.verticalPadding) < 1,
            "留白没有被正文宿主盖住，点它不会有反应"
        )
        #expect(
            abs(body.rect.height - (ClipboardLayout.rowHeight + ClipboardLayout.verticalPadding)) < 1,
            "正文宿主没有连留白一起接住"
        )
    }
}

@Suite("行的命中分区")
@MainActor
struct RowHitRegionTests {
    @Test("整行宿主覆盖正文与行尾")
    func rowHostCoversBodyAndTrailer() throws {
        let (host, window, _) = try makeRowHost(rowCount: 1)
        defer { window.orderOut(nil) }

        let rowHost = try #require(
            interactionHosts(in: host).max { $0.rect.width < $1.rect.width }
        )
        #expect(
            rowHost.rect.contains(CGPoint(x: rowHost.rect.minX + 40, y: rowHost.rect.midY)),
            "正文没有整行宿主覆盖，单击选中会失效"
        )
        #expect(
            rowHost.rect.contains(CGPoint(x: rowHost.rect.maxX - 10, y: rowHost.rect.midY)),
            "行尾滚动条留白没有整行宿主覆盖，右键弹不出菜单"
        )
    }

    @Test("编号占位时不保留看不见的复制热区")
    func shortcutNumberRemovesCopyHitTarget() throws {
        let (host, window, _) = try makeRowHost(rowCount: 1, shortcutNumber: 1)
        defer { window.orderOut(nil) }

        #expect(copyHitTargets(in: host).isEmpty, "编号显示时点行尾不该还在悄悄复制")
    }

    @Test("复制命中目标与按钮矩形同源")
    func copyHitTargetMatchesButtonRect() throws {
        let (host, window, context) = try makeRowHost(rowCount: 1)
        defer { window.orderOut(nil) }

        let rowHost = try #require(
            interactionHosts(in: host).max { $0.rect.width < $1.rect.width }
        )
        let target = try #require(copyHitTargets(in: host).first)

        let trailingInset = ClipboardLayout.rowCopyButtonTrailingInset(
            usesOverlayScrollers: context.scrollerLayout.usesOverlayScrollers
        )
        let buttonRect = ClipboardLayout.rowCopyButtonRect(listTopPadding: 0)
        let expected = CGRect(
            x: rowHost.rect.maxX - trailingInset - buttonRect.width,
            y: rowHost.rect.minY + buttonRect.minY,
            width: buttonRect.width,
            height: buttonRect.height
        )
        #expect(abs(target.rect.minX - expected.minX) < 0.5, "命中目标没有对齐按钮（x）")
        #expect(abs(target.rect.minY - expected.minY) < 0.5, "命中目标没有对齐按钮（y）")
        #expect(abs(target.rect.width - expected.width) < 0.5)
        #expect(abs(target.rect.height - expected.height) < 0.5)
    }
}
