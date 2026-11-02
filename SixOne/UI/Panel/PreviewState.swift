//
//  PreviewState.swift
//  SixOne
//
//  预览的对外门面：组合呈现、编辑与文件组三块状态，调用方无需感知拆分。
//

import Foundation
import Observation

/// 组内列表的程序化滚动请求；同一目标重复点选也要再发。
enum GroupScrollRequest: Equatable {
    case row(Int)
    case top
}

@Observable
final class PreviewState {
    let presentation = PreviewPresentationState()
    let editing = PreviewEditingState()
    let group = FileGroupPreviewState()

    // MARK: - 呈现

    var item: ClipboardItem? {
        get { presentation.item }
        set { presentation.item = newValue }
    }

    var showsFormatting: Bool {
        get { presentation.showsFormatting }
        set { presentation.showsFormatting = newValue }
    }

    var scopedFileURL: ScopedFileURL? {
        get { presentation.scopedFileURL }
        set { presentation.scopedFileURL = newValue }
    }

    var scopedGroupURLs: [ScopedFileURL?] {
        get { presentation.scopedGroupURLs }
        set { presentation.scopedGroupURLs = newValue }
    }

    // MARK: - 编辑

    var isEditing: Bool {
        get { editing.isEditing }
        set { editing.isEditing = newValue }
    }

    var shouldCommitEditing: Bool {
        get { editing.shouldCommitEditing }
        set { editing.shouldCommitEditing = newValue }
    }

    var hasUnsavedChanges: Bool {
        get { editing.hasUnsavedChanges }
        set { editing.hasUnsavedChanges = newValue }
    }

    var saveRequestID: Int { editing.saveRequestID }

    func startEditing() {
        // 超上限的正文只渲染了开头，编辑会把这截写回条目。
        guard item?.exceedsTextPreviewLimit != true else { return }
        editing.start()
    }
    func finishEditing() { editing.finish() }
    func requestSave() { editing.requestSave() }
    func cancelEditing() { editing.cancel() }

    // MARK: - 文件组

    var groupFileIndex: Int? { group.fileIndex }
    var groupSelectedIndex: Int? { group.selectedIndex }
    var groupFilterText: String { group.filterText }

    var isGroupFilterFocused: Bool {
        get { group.isFilterFocused }
        set { group.isFilterFocused = newValue }
    }

    var groupFilterNeedsFocus: Bool { group.filterNeedsFocus }
    var groupFilterFocusRequestID: Int { group.filterFocusRequestID }
    var groupFilterBlurRequestID: Int { group.filterBlurRequestID }
    var groupScrollRequest: GroupScrollRequest? { group.scrollRequest }
    var groupScrollRequestID: Int { group.scrollRequestID }

    var groupVisibleRowRange: ClosedRange<Int>? {
        get { group.visibleRowRange }
        set { group.visibleRowRange = newValue }
    }

    var groupCopyFeedbackIndex: Int? { group.copyFeedbackIndex }
    var groupCopyFeedbackRevision: Int { group.copyFeedbackRevision }

    /// 单文件态是正在看的文件，列表态是选中的行；nil 时键盘动作按整条处理。
    var focusedGroupFileIndex: Int? { group.focusedFileIndex }

    var isGroupFilterActive: Bool { group.isFilterActive }

    /// 预览停在组内列表。
    var isGroupOverview: Bool { group.isOverview(item: presentation.item) }

    var visibleGroupFileIndices: [Int] {
        group.visibleIndices(item: presentation.item, scopedURLs: presentation.scopedGroupURLs)
    }

    /// 更新筛选词；选中行被筛掉时清空选中，并重新定位滚动。
    func setGroupFilterText(_ text: String) {
        group.setFilterText(text, item: presentation.item, scopedURLs: presentation.scopedGroupURLs)
    }

    /// ⌘F 聚焦顶栏筛选框；视图重建时靠 `groupFilterNeedsFocus` 补聚焦。
    func focusGroupFilter() { group.focusFilter() }

    /// 焦点落定后清掉待聚焦标记，避免下次重建再抢焦点。
    func groupFilterFocusDidChange(_ focused: Bool) { group.filterFocusDidChange(focused) }

    func cancelGroupFilter() {
        group.cancelFilter(item: presentation.item, scopedURLs: presentation.scopedGroupURLs)
    }

    func dismissGroupFilter() { group.dismissFilter() }

    /// ↓ 进列表：已有选中保持不变，否则落到第一行。
    func moveFromGroupFilterToList() {
        group.moveFromFilterToList(item: presentation.item, scopedURLs: presentation.scopedGroupURLs)
    }

    func releaseGroupFilterFocus() { group.releaseFilterFocus() }
    func showGroupFile(_ index: Int) { group.showFile(index) }
    func showGroupOverview() { group.showOverview() }
    func selectGroupFile(_ index: Int?) { group.selectFile(index) }

    /// 触发某项的复制反馈。
    func markGroupFileCopied(at index: Int) { group.markFileCopied(at: index) }

    /// 可见位置映射回组内原始下标。
    func groupFileIndex(atVisiblePosition position: Int) -> Int? {
        group.fileIndex(atVisiblePosition: position, visibleIndices: visibleGroupFileIndices)
    }

    func canMoveGroupSelection(by delta: Int, visibleIndices: [Int]) -> Bool {
        group.canMoveSelection(by: delta, visibleIndices: visibleIndices)
    }

    /// 列表态移动一行；返回 false 表示已到边界，不再切换外层历史。
    @discardableResult
    func moveGroupSelection(by delta: Int, visibleIndices: [Int]) -> Bool {
        group.moveSelection(by: delta, visibleIndices: visibleIndices)
    }

    @discardableResult
    func jumpGroupSelection(toFirst: Bool, visibleIndices: [Int]) -> Bool {
        group.jumpSelection(toFirst: toFirst, visibleIndices: visibleIndices)
    }

    @discardableResult
    func stepGroupFile(delta: Int, visibleIndices: [Int]) -> Bool {
        group.stepFile(delta: delta, visibleIndices: visibleIndices)
    }

    @discardableResult
    func jumpGroupFile(toFirst: Bool, visibleIndices: [Int]) -> Bool {
        group.jumpFile(toFirst: toFirst, visibleIndices: visibleIndices)
    }

    /// 单文件态在筛选结果里的位置（1-based）与总数；无筛选时为组内原始位置。
    var viewingGroupFilePosition: (position: Int, total: Int)? {
        group.viewingPosition(item: presentation.item, scopedURLs: presentation.scopedGroupURLs)
    }

    // MARK: - 关闭

    /// 关闭预览：释放安全作用域访问权并清空三块状态。面板收起不走这里，收起只是挂起。
    func close() {
        presentation.reset()
        editing.reset()
        group.reset()
    }
}
