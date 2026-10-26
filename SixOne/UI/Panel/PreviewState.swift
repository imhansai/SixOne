//
//  PreviewState.swift
//  SixOne

import Foundation
import Observation

/// 组内列表的程序化滚动请求；同一目标重复点选也要再发。
enum GroupScrollRequest: Equatable {
    case row(Int)
    case top
}

@Observable
final class PreviewState {
    var item: ClipboardItem?
    var isEditing = false
    /// 退出编辑时是否落盘；只有「完成」置位。`close()` 也会把 isEditing 置 false，需要这个区分。
    var shouldCommitEditing = false
    /// 是否按原始格式显示；每次呈现预览都经 `close()` 复位，默认从纯文本开始。
    var showsFormatting = false
    var hasUnsavedChanges = false
    private(set) var saveRequestID = 0
    /// bookmark 解析并 start 后的 URL；预览关闭时统一停止访问。
    var scopedFileURL: ScopedFileURL?
    var scopedGroupURLs: [ScopedFileURL?] = []
    /// 单文件查看态正在看的文件；nil 表示停在列表总览。
    private(set) var groupFileIndex: Int?
    private(set) var groupSelectedIndex: Int?
    private(set) var groupFilterText = ""
    var isGroupFilterFocused = false
    /// 视图重建时据此补一次 ⌘F 首次聚焦。
    private(set) var groupFilterNeedsFocus = false
    private(set) var groupFilterFocusRequestID = 0
    private(set) var groupFilterBlurRequestID = 0
    private(set) var groupScrollRequest: GroupScrollRequest?
    private(set) var groupScrollRequestID = 0

    /// 单文件态是正在看的文件，列表态是选中的行；nil 时键盘动作按整条处理。
    var focusedGroupFileIndex: Int? { groupFileIndex ?? groupSelectedIndex }

    var isGroupFilterActive: Bool {
        !groupFilterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var visibleGroupFileIndices: [Int] {
        guard let item, item.kind == .file, item.fileCount > 1 else { return [] }
        let all = Array(0..<item.fileCount)
        guard isGroupFilterActive else { return all }
        let query = groupFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { matchesGroupFilter(at: $0, query: query) }
    }

    private func matchesGroupFilter(at index: Int, query: String) -> Bool {
        guard let item, item.allFilePaths.indices.contains(index) else { return false }
        let path = resolvedGroupPath(at: index, of: item)
        guard let path else { return false }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.localizedStandardContains(query) || path.localizedStandardContains(query)
    }

    /// 优先用 bookmark 解析后的路径，失联时回落到捕获路径。
    private func resolvedGroupPath(at index: Int, of item: ClipboardItem) -> String? {
        guard item.allFilePaths.indices.contains(index) else { return nil }
        if scopedGroupURLs.indices.contains(index), let url = scopedGroupURLs[index] {
            return url.url.path
        }
        return item.allFilePaths[index]
    }

    /// 更新筛选词；选中行被筛掉时清空选中，并重新定位滚动。
    func setGroupFilterText(_ text: String) {
        groupFilterText = text
        if let selected = groupSelectedIndex, !visibleGroupFileIndices.contains(selected) {
            groupSelectedIndex = nil
        }
        if let selected = groupSelectedIndex {
            requestGroupScroll(.row(selected))
        } else {
            requestGroupScroll(.top)
        }
    }

    private func requestGroupScroll(_ request: GroupScrollRequest) {
        groupScrollRequest = request
        groupScrollRequestID += 1
    }

    /// ⌘F 聚焦顶栏筛选框；视图重建时靠 `groupFilterNeedsFocus` 补聚焦。
    func focusGroupFilter() {
        groupFilterNeedsFocus = true
        groupFilterFocusRequestID += 1
    }

    /// 焦点落定后清掉待聚焦标记，避免下次重建再抢焦点。
    func groupFilterFocusDidChange(_ focused: Bool) {
        isGroupFilterFocused = focused
        groupFilterNeedsFocus = false
    }

    func cancelGroupFilter() {
        if groupFilterText.isEmpty {
            dismissGroupFilter()
        } else {
            setGroupFilterText("")
        }
    }

    func dismissGroupFilter() {
        groupFilterBlurRequestID += 1
        isGroupFilterFocused = false
        groupFilterNeedsFocus = false
    }

    /// ↓ 进列表：已有选中保持不变，否则落到第一行。
    func moveFromGroupFilterToList() {
        dismissGroupFilter()
        if groupSelectedIndex == nil {
            moveGroupSelection(by: 1, visibleIndices: visibleGroupFileIndices)
        }
    }

    func releaseGroupFilterFocus() {
        isGroupFilterFocused = false
        groupFilterNeedsFocus = false
    }

    func startEditing() {
        shouldCommitEditing = false
        hasUnsavedChanges = false
        isEditing = true
    }

    /// 「完成」：标记落盘再退出；已不在编辑态时不再改标记，避免重复调用翻成取消。
    func finishEditing() {
        guard isEditing else { return }
        shouldCommitEditing = true
        hasUnsavedChanges = false
        isEditing = false
    }

    /// ⌘S：请求保存但保持编辑态。
    func requestSave() {
        guard isEditing else { return }
        saveRequestID += 1
    }

    /// 取消编辑：退出但不落盘，正文恢复为进入编辑前的快照。
    func cancelEditing() {
        guard isEditing else { return }
        shouldCommitEditing = false
        hasUnsavedChanges = false
        isEditing = false
    }

    func showGroupFile(_ index: Int) {
        groupFileIndex = index
        groupSelectedIndex = index
        requestGroupScroll(.row(index))
        if isGroupFilterFocused || groupFilterNeedsFocus {
            dismissGroupFilter()
        }
    }

    func showGroupOverview() {
        groupFileIndex = nil
        if let selected = groupSelectedIndex {
            requestGroupScroll(.row(selected))
        }
    }

    func selectGroupFile(_ index: Int?) {
        groupSelectedIndex = index
        if let index {
            requestGroupScroll(.row(index))
        }
    }

    func canMoveGroupSelection(by delta: Int, visibleIndices: [Int]) -> Bool {
        guard !visibleIndices.isEmpty, abs(delta) == 1 else { return false }
        guard let current = groupSelectedIndex, let position = visibleIndices.firstIndex(of: current) else {
            return delta > 0
        }
        return visibleIndices.indices.contains(position + delta)
    }

    /// 列表态移动一行；返回 false 表示已到边界，不再切换外层历史。
    @discardableResult
    func moveGroupSelection(by delta: Int, visibleIndices: [Int]) -> Bool {
        guard canMoveGroupSelection(by: delta, visibleIndices: visibleIndices) else { return false }
        guard let current = groupSelectedIndex, let position = visibleIndices.firstIndex(of: current) else {
            selectGroupFile(visibleIndices[0])
            return true
        }
        selectGroupFile(visibleIndices[position + delta])
        return true
    }

    @discardableResult
    func jumpGroupSelection(toFirst: Bool, visibleIndices: [Int]) -> Bool {
        guard let target = toFirst ? visibleIndices.first : visibleIndices.last else { return false }
        guard groupSelectedIndex != target else { return false }
        selectGroupFile(target)
        return true
    }

    @discardableResult
    func stepGroupFile(delta: Int, visibleIndices: [Int]) -> Bool {
        guard let current = groupFileIndex,
              let position = visibleIndices.firstIndex(of: current) else { return false }
        let target = position + delta
        guard visibleIndices.indices.contains(target) else { return false }
        showGroupFile(visibleIndices[target])
        return true
    }

    @discardableResult
    func jumpGroupFile(toFirst: Bool, visibleIndices: [Int]) -> Bool {
        guard let current = groupFileIndex, visibleIndices.contains(current),
              let target = toFirst ? visibleIndices.first : visibleIndices.last else { return false }
        guard target != current else { return false }
        showGroupFile(target)
        return true
    }

    /// 单文件态在筛选结果里的位置（1-based）与总数；无筛选时为组内原始位置。
    var viewingGroupFilePosition: (position: Int, total: Int)? {
        guard let current = groupFileIndex else { return nil }
        let visible = visibleGroupFileIndices
        guard let offset = visible.firstIndex(of: current) else { return nil }
        return (offset + 1, visible.count)
    }

    /// 关闭预览：释放安全作用域访问权并清空状态。面板收起不走这里，收起只是挂起。
    func close() {
        scopedFileURL?.stopAccessIfNeeded()
        scopedFileURL = nil
        for url in scopedGroupURLs { url?.stopAccessIfNeeded() }
        scopedGroupURLs = []
        groupFileIndex = nil
        groupSelectedIndex = nil
        groupFilterText = ""
        isGroupFilterFocused = false
        groupFilterNeedsFocus = false
        groupScrollRequest = nil
        groupScrollRequestID = 0
        item = nil
        shouldCommitEditing = false
        hasUnsavedChanges = false
        isEditing = false
        showsFormatting = false
    }
}
