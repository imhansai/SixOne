//
//  GroupListTableViewTests.swift
//  SixOneTests
//  文件组列表在离屏窗口装配一次：行、宿主、滚动请求、筛选与选中同步。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("文件组列表装配")
@MainActor
struct GroupListTableViewTests {
    private static let viewportSize = NSSize(width: ClipboardLayout.panelWidth, height: 491)

    private func makeFiles(_ count: Int) -> [GroupFileEntry] {
        (0..<count).map { index in
            GroupFileEntry(index: index, path: "/tmp/sixone-group-\(index).txt", url: nil)
        }
    }

    private func makeView(
        context: PanelContext,
        files: [GroupFileEntry],
        selectedIndex: Int? = nil,
        isListActive: Bool = true,
        scrollRequest: GroupScrollRequest? = nil,
        scrollRequestID: Int = 0,
        isScrollBlocked: Bool = false,
        quickPasteRange: ClosedRange<Int>? = nil,
        onVisibleRowRangeChanged: ((ClosedRange<Int>) -> Void)? = nil,
        onSelect: @escaping (Int?) -> Void = { _ in }
    ) -> AnyView {
        AnyView(
            GroupListTableView(
                context: context,
                files: files,
                selectedIndex: selectedIndex,
                isListActive: isListActive,
                sourceAppBundleIdentifier: nil,
                thumbnailCache: context.caches.fileGroupThumbnails,
                scrollRequest: scrollRequest,
                scrollRequestID: scrollRequestID,
                isScrollBlocked: isScrollBlocked,
                quickPasteRange: quickPasteRange,
                onVisibleRowRangeChanged: onVisibleRowRangeChanged,
                locale: RuntimeLanguage.shared.locale,
                displayScale: 2,
                onSelect: onSelect,
                onPreview: { _ in },
                onCommand: { _, _ in },
                onShare: { _, _ in }
            )
        )
    }

    @Test("组列表把行落进 NSTableView，行交互宿主就在单元格里")
    func rendersRowsIntoTableView() async throws {
        let context = try TestPanel.context()
        let files = makeFiles(40)
        let (host, window) = OffscreenHost.make(
            makeView(context: context, files: files),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "组列表没有建出滚动视图")
        #expect(scrollView is ListScrollView, "组列表没有用共用的同步滚动视图")
        #expect(scrollView.contentView is ListClipView, "组列表没有用关闭动画的 clip view")
        let tableView = try #require(scrollView.documentView as? NSTableView, "组列表容器不是 NSTableView")
        #expect(await Wait.until { tableView.numberOfRows == files.count }, "表格行数与数据源对不上")
        #expect(tableView.rows(in: tableView.visibleRect).length > 0, "视口里一行都没有")

        let hostsMounted = await Wait.until {
            !OffscreenHost.allSubviews(of: host).compactMap { $0 as? RowInteractionHost.HostView }.isEmpty
        }
        #expect(hostsMounted, "行交互宿主没挂进单元格")
        #expect(abs(tableView.frame.width - scrollView.contentView.bounds.width) < 1, "表格没有铺满可视宽度")
    }

    @Test("滚动请求按原始下标定位")
    func scrollRequestUsesOriginalIndex() async throws {
        let context = try TestPanel.context()
        let files = makeFiles(120)
        let (host, window) = OffscreenHost.make(
            makeView(context: context, files: files, scrollRequest: .row(100), scrollRequestID: 1),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host), "组列表没有建出滚动视图")
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == files.count }, "行没有落进表格")

        let reached = await Wait.until(timeout: .seconds(2)) {
            scrollView.documentVisibleRect.contains(tableView.rect(ofRow: 100))
        }
        #expect(reached, "滚动请求没有按原始下标滚到位")

        host.rootView = makeView(
            context: context,
            files: files,
            scrollRequest: .row(3),
            scrollRequestID: 2
        )
        let returned = await Wait.until(timeout: .seconds(2)) {
            scrollView.documentVisibleRect.contains(tableView.rect(ofRow: 3))
        }
        #expect(returned, "第二个滚动请求没有生效")
    }

    @Test("筛选后的行数与选中同步到表格")
    func syncsFilteredRowsAndSelection() async throws {
        let context = try TestPanel.context()
        let all = makeFiles(20)
        let (host, window) = OffscreenHost.make(
            makeView(context: context, files: all, selectedIndex: 3),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host))
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == all.count }, "全量行没有落进表格")

        let filtered = [all[3], all[7]]
        host.rootView = makeView(context: context, files: filtered, selectedIndex: 3)
        #expect(await Wait.until { tableView.numberOfRows == filtered.count }, "筛选后的行数没同步")
        #expect(await Wait.until { tableView.selectedRow == 0 }, "选中没有按筛选后的位置镜像")
    }

    @Test("点表体空白取消选中")
    func clickingEmptyAreaClearsSelection() async throws {
        let context = try TestPanel.context()
        let files = makeFiles(2)
        let probe = SelectionProbe()
        let (host, window) = OffscreenHost.make(
            makeView(context: context, files: files, selectedIndex: 0, onSelect: { probe.values.append($0) }),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host))
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == files.count }, "行没有落进表格")
        #expect(await Wait.until { tableView.bounds.height > 200 }, "表格没有铺满视口，空白点击没有落点")

        let pointInTable = NSPoint(x: 40, y: tableView.bounds.height - 10)
        let pointInWindow = tableView.convert(pointInTable, to: nil)
        func mouseEvent(_ type: NSEvent.EventType) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type,
                location: pointInWindow,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
        }
        NSApp.sendEvent(try mouseEvent(.leftMouseDown))
        NSApp.sendEvent(try mouseEvent(.leftMouseUp))
        let selected = try #require(probe.values.last, "点空白没有回调")
        #expect(selected == nil, "点空白没有取消选中")
    }

    @Test("来回扫全表时行视图与单元格保持有界复用")
    func rowViewsAreReusedAcrossFullSweeps() async throws {
        let context = try TestPanel.context()
        let files = makeFiles(80)
        let (host, window) = OffscreenHost.make(
            makeView(context: context, files: files),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host))
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == files.count }, "行没有落进表格")

        var seenRowViews = Set<ObjectIdentifier>()
        var seenCells = Set<ObjectIdentifier>()
        func sampleVisibleRows() {
            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.location != NSNotFound, visible.length > 0 else { return }
            for row in visible.location..<(visible.location + visible.length) {
                if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) {
                    seenRowViews.insert(ObjectIdentifier(rowView))
                }
                if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) {
                    seenCells.insert(ObjectIdentifier(cell))
                }
            }
        }

        var requestID = 0
        var misses = 0
        let targets = Array(stride(from: 0, to: files.count, by: 5)) + [files.count - 1]
        let passes = [targets, Array(targets.reversed())]
        for pass in passes {
            for index in pass {
                requestID += 1
                host.rootView = makeView(
                    context: context,
                    files: files,
                    scrollRequest: .row(files[index].index),
                    scrollRequestID: requestID
                )
                let reached = await Wait.until(timeout: .seconds(2), interval: .milliseconds(5)) {
                    scrollView.documentVisibleRect.contains(tableView.rect(ofRow: index))
                }
                if !reached { misses += 1 }
                sampleVisibleRows()
            }
        }

        #expect(misses == 0, "用例没走到真实滚动路径（\(misses) 步没滚到目标）")
        #expect(seenRowViews.count <= 48, "行视图没有被复用：\(seenRowViews.count) 个实例")
        #expect(seenCells.count <= 48, "单元格没有被复用：\(seenCells.count) 个实例")
    }

    @Test("组列表发布完整可见范围，滚动后按新范围重发")
    func publishesFullyVisibleRowRange() async throws {
        let context = try TestPanel.context()
        let files = makeFiles(40)
        let probeID = UUID()
        let (host, window) = OffscreenHost.make(
            makeView(
                context: context,
                files: files,
                onVisibleRowRangeChanged: { GroupVisibleRangeProbe.record(probeID, range: $0) }
            ),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host))
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == files.count }, "行没有落进表格")

        #expect(await Wait.until { !GroupVisibleRangeProbe.ranges(probeID).isEmpty },
                "完整可见范围没有发布，快速粘贴编号没有依据")
        let first = try #require(GroupVisibleRangeProbe.ranges(probeID).last)
        #expect(first.lowerBound == 0, "首屏应从第 0 行起编号")
        #expect(tableView.visibleRect.contains(tableView.rect(ofRow: first.upperBound)),
                "发布的末行并不完整可见")

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: ClipboardLayout.rowHeight * 5))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let scrolled = await Wait.until {
            GroupVisibleRangeProbe.ranges(probeID).last?.lowerBound != first.lowerBound
        }
        #expect(scrolled, "滚动后没有按新的完整可见范围重发编号依据")
    }

    @Test("重建列表后即使可见范围相同也重新发布")
    func republishesSameRangeAfterReload() async throws {
        let context = try TestPanel.context()
        let files = makeFiles(6)
        let probeID = UUID()
        func view(_ files: [GroupFileEntry]) -> AnyView {
            makeView(context: context, files: files, onVisibleRowRangeChanged: {
                GroupVisibleRangeProbe.record(probeID, range: $0)
            })
        }

        let (host, window) = OffscreenHost.make(view(files), size: Self.viewportSize)
        defer { window.orderOut(nil) }
        #expect(await Wait.until { !GroupVisibleRangeProbe.ranges(probeID).isEmpty })
        let count = GroupVisibleRangeProbe.ranges(probeID).count

        // 行 id 变化触发重建，可见范围仍是 0...5。
        host.rootView = view(Array(files.reversed()))
        #expect(await Wait.until { GroupVisibleRangeProbe.ranges(probeID).count > count },
                "重建后没有重发同一可见范围")
    }

    @Test("编号占位时组内行不再保留行尾复制热区")
    func quickPasteRangeRemovesCopyHitTargets() async throws {
        let context = try TestPanel.context()
        let files = makeFiles(6)
        let (host, window) = OffscreenHost.make(
            makeView(context: context, files: files),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host))
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == files.count }, "行没有落进表格")
        #expect(await Wait.until { !copyHitTargets(in: host).isEmpty },
                "未显示编号时应保留行尾复制热区")

        host.rootView = makeView(
            context: context,
            files: files,
            quickPasteRange: 0...(files.count - 1)
        )
        #expect(await Wait.until { copyHitTargets(in: host).isEmpty },
                "编号显示时点行尾不该还在悄悄复制")
    }

    @Test("行状态按原始下标复用")
    func rowStateStoreReusesStatePerIndex() {
        let store = GroupRowStateStore()
        let state = store.state(for: 3)
        #expect(store.state(for: 3) === state, "同一文件应取到同一份行状态")
        #expect(store.state(for: 7) !== state, "不同文件不应共享行状态")
    }

    @Test("确认弹窗压着时组列表停掉滚动，关掉后恢复")
    func confirmationBlocksGroupListScrolling() async throws {
        let context = try TestPanel.context()
        let files = makeFiles(20)
        let (host, window) = OffscreenHost.make(
            makeView(context: context, files: files),
            size: Self.viewportSize
        )
        defer { window.orderOut(nil) }

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host))
        let listScrollView = try #require(scrollView as? ListScrollView)
        #expect(!listScrollView.isScrollBlocked, "默认就该能滚")

        host.rootView = makeView(context: context, files: files, isScrollBlocked: true)
        #expect(await Wait.until { listScrollView.isScrollBlocked }, "确认弹窗压着时没有停掉组列表滚动")

        host.rootView = makeView(context: context, files: files, isScrollBlocked: false)
        #expect(await Wait.until { !listScrollView.isScrollBlocked }, "关掉确认弹窗后没有恢复组列表滚动")
    }
}

@Suite("文件组快速粘贴提示")
@MainActor
struct GroupQuickPasteHintTests {
    @Test("按住 ⌘ 后组内行换成编号并收起复制热区，松开恢复")
    func holdingCommandReplacesCopyButtonsWithNumbers() async throws {
        let context = try TestPanel.context()
        let paths = (0..<6).map { "/tmp/sixone-quick-\($0).txt" }
        let item = ClipboardItem(kind: .file, filePaths: paths)
        context.previewState.item = item
        context.previewState.scopedGroupURLs = paths.map {
            ScopedFileURL(url: URL(fileURLWithPath: $0), needsStop: false)
        }
        let urls = context.previewState.scopedGroupURLs.map { $0?.url }

        let (host, window) = OffscreenHost.make(
            AnyView(
                FileGroupContent(item: item, groupURLs: urls)
                    .environment(context)
                    .environment(\.locale, RuntimeLanguage.shared.locale)
            ),
            size: ClipboardLayout.panelSize
        )
        defer { window.orderOut(nil) }

        let scrollView = try #require(await OffscreenHost.waitForScrollView(in: host))
        let tableView = try #require(scrollView.documentView as? NSTableView)
        #expect(await Wait.until { tableView.numberOfRows == paths.count }, "行没有落进表格")
        #expect(await Wait.until { context.previewState.groupVisibleRowRange != nil },
                "组列表没有发布完整可见范围")
        #expect(await Wait.until { !copyHitTargets(in: host).isEmpty },
                "未按住 ⌘ 时应保留行尾复制热区")

        context.quickPasteHintState.handleModifiers(.command)
        #expect(await Wait.until { context.quickPasteHintState.isShowing },
                "按住 ⌘ 没有进入编号提示")
        #expect(await Wait.until { copyHitTargets(in: host).isEmpty },
                "按住 ⌘ 后行尾复制热区没有让位给编号")

        context.quickPasteHintState.handleModifiers([])
        #expect(!context.quickPasteHintState.isShowing)
        #expect(await Wait.until { !copyHitTargets(in: host).isEmpty },
                "松开 ⌘ 后行尾复制热区没有恢复")
    }

    @Test("⌘C 等外部复制也会让组内对应行闪对勾")
    func groupCopyFeedbackReachesRow() async throws {
        let context = try TestPanel.context()
        let file = GroupFileEntry(index: 1, path: "/tmp/sixone-copy-1.txt", url: nil)
        let state = FileGroupRowState()
        let (host, window) = OffscreenHost.make(
            AnyView(
                FileGroupRow(
                    file: file,
                    state: state,
                    rowID: file.rowID,
                    clickTracker: RowClickTracker(),
                    isSelected: false,
                    isListActive: true,
                    sourceAppBundleIdentifier: nil,
                    thumbnailCache: context.caches.fileGroupThumbnails,
                    displayScale: 2,
                    onSelect: { _ in },
                    onPreview: { _ in },
                    onCommand: { _, _ in },
                    onShare: { _, _ in }
                )
                .environment(context)
            ),
            size: NSSize(width: ClipboardLayout.panelWidth, height: ClipboardLayout.rowHeight)
        )
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()

        context.previewState.markGroupFileCopied(at: 1)
        #expect(await Wait.until { state.isCopied }, "复制反馈没有落到对应行")
    }
}

@MainActor
private func copyHitTargets(in host: NSView) -> [RowCopyHitTarget.HostView] {
    OffscreenHost.allSubviews(of: host).compactMap { $0 as? RowCopyHitTarget.HostView }
}

@MainActor
private final class SelectionProbe {
    var values: [Int?] = []
}

/// 按用例 id 记录可见范围，避免并行用例互相清计数。
private enum GroupVisibleRangeProbe {
    nonisolated(unsafe) static var published: [UUID: [ClosedRange<Int>]] = [:]

    nonisolated static func record(_ id: UUID, range: ClosedRange<Int>) {
        published[id, default: []].append(range)
    }

    nonisolated static func ranges(_ id: UUID) -> [ClosedRange<Int>] {
        published[id] ?? []
    }
}
