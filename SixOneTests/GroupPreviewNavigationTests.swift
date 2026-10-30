//
//  GroupPreviewNavigationTests.swift
//  SixOneTests

import Foundation
import Testing
@testable import SixOne

@Suite("文件组预览的键盘切换")
struct GroupPreviewNavigationTests {
    private var allIndices: [Int] { Array(0..<10) }

    @Test("未选中时 ↓ 选中首行；↑ 不选中末行")
    func unselectedOnlyMovesDown() {
        let state = PreviewState()
        #expect(state.focusedGroupFileIndex == nil)
        #expect(!state.canMoveGroupSelection(by: -1, visibleIndices: allIndices))
        #expect(!state.moveGroupSelection(by: -1, visibleIndices: allIndices))
        #expect(state.focusedGroupFileIndex == nil, "↑ 不再从末行开始")

        #expect(state.canMoveGroupSelection(by: 1, visibleIndices: allIndices))
        #expect(state.moveGroupSelection(by: 1, visibleIndices: allIndices))
        #expect(state.focusedGroupFileIndex == 0)
    }

    @Test("上下移动一行")
    func movesByOneRow() {
        let state = PreviewState()
        state.selectGroupFile(4)
        #expect(state.moveGroupSelection(by: 1, visibleIndices: allIndices))
        #expect(state.focusedGroupFileIndex == 5)
        #expect(state.moveGroupSelection(by: -1, visibleIndices: allIndices))
        #expect(state.focusedGroupFileIndex == 4)
    }

    @Test("列表两端返回 false，交给历史条目切换")
    func clampsAtListEnds() {
        let state = PreviewState()
        state.selectGroupFile(0)
        #expect(state.canMoveGroupSelection(by: -1, visibleIndices: allIndices) == false)
        #expect(state.moveGroupSelection(by: -1, visibleIndices: allIndices) == false)
        #expect(state.focusedGroupFileIndex == 0)

        state.selectGroupFile(9)
        #expect(state.canMoveGroupSelection(by: 1, visibleIndices: allIndices) == false)
        #expect(state.moveGroupSelection(by: 1, visibleIndices: allIndices) == false)
        #expect(state.focusedGroupFileIndex == 9)
    }

    @Test("没有可见行时上下键没有落点")
    func emptyVisibleRows() {
        let state = PreviewState()
        #expect(state.canMoveGroupSelection(by: 1, visibleIndices: []) == false)
        #expect(state.moveGroupSelection(by: 1, visibleIndices: []) == false)
        #expect(state.moveGroupSelection(by: -1, visibleIndices: []) == false)
        #expect(state.focusedGroupFileIndex == nil)
    }

    @Test("只能在筛选后的可见行之间移动")
    func movesWithinVisibleIndices() {
        let state = PreviewState()
        let visible = [1, 4, 8]
        state.selectGroupFile(4)
        #expect(state.moveGroupSelection(by: 1, visibleIndices: visible))
        #expect(state.focusedGroupFileIndex == 8)
        #expect(state.moveGroupSelection(by: 1, visibleIndices: visible) == false)
        #expect(state.moveGroupSelection(by: -2, visibleIndices: visible) == false,
                "一步只走一行")
        state.selectGroupFile(1)
        #expect(state.moveGroupSelection(by: -1, visibleIndices: visible) == false)
    }

    @Test("查看态切换按可见顺序相邻，到两端停住")
    func viewingStepsBetweenNeighbours() {
        let state = PreviewState()
        let visible = [2, 5, 8]
        state.showGroupFile(5)
        #expect(state.focusedGroupFileIndex == 5)
        #expect(state.stepGroupFile(delta: 1, visibleIndices: visible))
        #expect(state.groupFileIndex == 8)
        #expect(state.groupSelectedIndex == 8)
        #expect(state.stepGroupFile(delta: 1, visibleIndices: visible) == false)

        state.showGroupFile(2)
        #expect(state.stepGroupFile(delta: -1, visibleIndices: visible) == false)
    }

    @Test("⌘↑ / ⌘↓ 在列表与查看态都跳到组内首个/最后一个")
    func jumpsWithinGroup() {
        let state = PreviewState()
        let visible = [2, 5, 8]

        #expect(state.jumpGroupSelection(toFirst: true, visibleIndices: visible))
        #expect(state.focusedGroupFileIndex == 2)
        #expect(state.jumpGroupSelection(toFirst: false, visibleIndices: visible))
        #expect(state.focusedGroupFileIndex == 8)

        state.showGroupFile(5)
        #expect(state.jumpGroupFile(toFirst: true, visibleIndices: visible))
        #expect(state.groupFileIndex == 2)
        #expect(state.jumpGroupFile(toFirst: false, visibleIndices: visible))
        #expect(state.groupFileIndex == 8)
        #expect(state.jumpGroupFile(toFirst: false, visibleIndices: visible) == false)
    }

    @Test("退回列表保留刚看过的行")
    func overviewKeepsSelection() {
        let state = PreviewState()
        state.showGroupFile(6)
        state.showGroupOverview()
        #expect(state.groupFileIndex == nil)
        #expect(state.groupSelectedIndex == 6)
        #expect(state.focusedGroupFileIndex == 6)
    }

    @Test("点空白取消选中后，键盘动作回落到整条条目")
    func clearingSelection() {
        let state = PreviewState()
        state.selectGroupFile(2)
        #expect(state.focusedGroupFileIndex == 2)
        state.selectGroupFile(nil)
        #expect(state.focusedGroupFileIndex == nil)
    }

    @Test("点同一行也会重新发滚动请求")
    func selectingSameRowRequestsScrollAgain() {
        let state = PreviewState()
        state.selectGroupFile(2)
        #expect(state.groupScrollRequest == .row(2))
        let firstID = state.groupScrollRequestID

        state.selectGroupFile(2)
        #expect(state.groupScrollRequest == .row(2))
        #expect(state.groupScrollRequestID == firstID + 1,
                "同一条目重复点选也要补一次留白")
    }

    @Test("关闭预览清掉聚焦状态")
    func closeResetsFocus() {
        let state = PreviewState()
        state.showGroupFile(2)
        state.close()
        #expect(state.groupFileIndex == nil)
        #expect(state.groupSelectedIndex == nil)
        #expect(state.focusedGroupFileIndex == nil)
    }
}

@Suite("文件组列表筛选")
@MainActor
struct GroupFileFilterTests {
    private func makeState(paths: [String]) -> PreviewState {
        let state = PreviewState()
        state.item = ClipboardItem(kind: .file, filePaths: paths)
        state.scopedGroupURLs = paths.map {
            ScopedFileURL(url: URL(fileURLWithPath: $0), needsStop: false)
        }
        return state
    }

    @Test("空筛选显示全部文件")
    func allFilesWithoutFilter() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.txt"])
        #expect(state.visibleGroupFileIndices == [0, 1])
    }

    @Test("筛选词变化作废旧可见范围，等列表重新发布")
    func filterChangeInvalidatesVisibleRange() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.txt", "/tmp/c.png"])
        state.groupVisibleRowRange = 0...2
        state.setGroupFilterText("png")
        #expect(state.groupVisibleRowRange == nil,
                "旧编号范围对应上一批可见行，重排前不能再用")
    }

    @Test("筛选后可见集未变时保留可见范围")
    func filterChangeKeepsRangeWhenSetUnchanged() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.png"])
        state.groupVisibleRowRange = 0...1
        state.setGroupFilterText("png")
        #expect(state.groupVisibleRowRange == 0...1)
    }

    @Test("筛选变化重新定位：无选中回顶，有选中带留白露出")
    func filterChangeRequestsScroll() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.png", "/tmp/c.png"])

        state.setGroupFilterText("png")
        #expect(state.groupScrollRequest == .top)

        state.selectGroupFile(1)
        #expect(state.groupScrollRequest == .row(1))

        state.setGroupFilterText("a.png")
        #expect(state.visibleGroupFileIndices == [0])
        #expect(state.groupScrollRequest == .top, "选中被筛掉后回顶")

        state.selectGroupFile(0)
        let requestID = state.groupScrollRequestID
        state.setGroupFilterText("a")
        #expect(state.groupScrollRequest == .row(0), "选中仍在结果里就把它露出来")
        #expect(state.groupScrollRequestID > requestID)
    }

    @Test("完整可见区位置映射回组内原始下标")
    func visiblePositionMapsToOriginalIndex() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.txt", "/tmp/c.png"])
        state.setGroupFilterText("png")
        #expect(state.groupFileIndex(atVisiblePosition: 0) == 0)
        #expect(state.groupFileIndex(atVisiblePosition: 1) == 2)
        #expect(state.groupFileIndex(atVisiblePosition: 2) == nil)
    }

    @Test("按文件名筛选，大小写不敏感")
    func filtersByName() {
        let state = makeState(paths: ["/tmp/Report.pdf", "/tmp/photo.png", "/tmp/report2.pdf"])
        state.setGroupFilterText("report")
        #expect(state.visibleGroupFileIndices == [0, 2])
    }

    @Test("按完整路径也能命中")
    func filtersByPath() {
        let state = makeState(paths: ["/Users/me/Docs/a.txt", "/Users/me/Images/b.png"])
        state.setGroupFilterText("images")
        #expect(state.visibleGroupFileIndices == [1])
    }

    @Test("筛选词忽略首尾空白")
    func trimsWhitespace() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.txt"])
        state.setGroupFilterText("  a.png  ")
        #expect(state.visibleGroupFileIndices == [0])
    }

    @Test("只有空白的筛选词不算筛选状态")
    func whitespaceIsNotAFilter() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.txt"])
        state.setGroupFilterText("   ")
        #expect(!state.isGroupFilterActive)
        #expect(state.visibleGroupFileIndices == [0, 1])

        state.setGroupFilterText("a")
        #expect(state.isGroupFilterActive)
    }

    @Test("选中项被筛掉时清空选中")
    func clearsHiddenSelection() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.txt"])
        state.selectGroupFile(1)
        state.setGroupFilterText("a.png")
        #expect(state.visibleGroupFileIndices == [0])
        #expect(state.focusedGroupFileIndex == nil)
    }

    @Test("选中项仍在筛选结果里时保留选中")
    func keepsVisibleSelection() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.txt"])
        state.selectGroupFile(0)
        state.setGroupFilterText("a")
        #expect(state.focusedGroupFileIndex == 0)
    }

    @Test("⌘F 推进聚焦请求，焦点由 SearchField 回报")
    func filterFocusRequest() {
        let state = PreviewState()
        #expect(!state.isGroupFilterFocused)
        state.focusGroupFilter()
        #expect(state.groupFilterFocusRequestID == 1)
        #expect(state.groupFilterNeedsFocus, "视图重建时要能补一次首次聚焦")
        state.groupFilterFocusDidChange(true)
        #expect(state.isGroupFilterFocused)
        #expect(!state.groupFilterNeedsFocus)
        state.groupFilterFocusDidChange(false)
        #expect(!state.isGroupFilterFocused)
    }

    @Test("查看态的位置与总数按筛选结果计算")
    func viewingPositionUsesFilteredResults() {
        let state = makeState(paths: ["/tmp/report-a.pdf", "/tmp/photo.png", "/tmp/report-b.pdf"])

        state.showGroupFile(1)
        #expect(state.viewingGroupFilePosition?.position == 2)
        #expect(state.viewingGroupFilePosition?.total == 3)

        state.setGroupFilterText("report")
        #expect(state.visibleGroupFileIndices == [0, 2])
        #expect(state.viewingGroupFilePosition == nil, "当前文件被筛掉时没有位置")

        state.showGroupFile(2)
        #expect(state.viewingGroupFilePosition?.position == 2)
        #expect(state.viewingGroupFilePosition?.total == 2)
    }

    @Test("筛选框 Esc：有词先清空并保持焦点，无词再退出")
    func cancelFilter() {
        let state = makeState(paths: ["/tmp/a.png"])
        state.focusGroupFilter()
        state.groupFilterFocusDidChange(true)
        state.setGroupFilterText("a")
        state.cancelGroupFilter()
        #expect(state.groupFilterText.isEmpty)
        #expect(state.isGroupFilterFocused, "清空后仍留在筛选框")
        state.cancelGroupFilter()
        #expect(!state.isGroupFilterFocused)
    }

    @Test("筛选框 ↓ 进列表：无选中时落到第一行，有选中时保持不变")
    func filterMoveDownEntersList() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.png"])
        state.focusGroupFilter()
        state.groupFilterFocusDidChange(true)

        state.moveFromGroupFilterToList()
        #expect(!state.isGroupFilterFocused)
        #expect(state.groupSelectedIndex == 0, "一次 ↓ 就要落到第一行")
        #expect(state.groupScrollRequest == .row(0))

        state.selectGroupFile(1)
        state.moveFromGroupFilterToList()
        #expect(state.groupSelectedIndex == 1, "已有选中时只退出焦点")
    }

    @Test("↓ 进列表只退出焦点，筛选词继续生效")
    func dismissKeepsActiveFilter() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.txt"])
        state.focusGroupFilter()
        state.setGroupFilterText("a")
        state.groupFilterFocusDidChange(true)
        state.dismissGroupFilter()
        #expect(!state.isGroupFilterFocused)
        #expect(state.groupFilterText == "a")
        #expect(state.visibleGroupFileIndices == [0])
    }

    @Test("进入单文件查看时交还筛选框焦点")
    func enteringFileViewDismissesFilterFocus() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.png"])
        state.focusGroupFilter()
        state.setGroupFilterText("a")
        state.groupFilterFocusDidChange(true)
        state.showGroupFile(0)
        #expect(!state.isGroupFilterFocused)
        #expect(state.groupFileIndex == 0)
    }

    @Test("关闭预览清掉筛选状态")
    func closeResetsFilter() {
        let state = makeState(paths: ["/tmp/a.png", "/tmp/b.txt"])
        state.focusGroupFilter()
        state.setGroupFilterText("a")
        state.close()
        #expect(state.groupFilterText.isEmpty)
        #expect(!state.isGroupFilterFocused)
        #expect(state.visibleGroupFileIndices.isEmpty)
    }
}
