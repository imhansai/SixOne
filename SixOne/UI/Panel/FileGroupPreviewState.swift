//
//  FileGroupPreviewState.swift
//  SixOne
//
//  文件组预览状态：组内选中、筛选、滚动请求与复制反馈。
//

import Foundation
import Observation

@Observable
final class FileGroupPreviewState {
    /// 单文件查看态正在看的文件；nil 表示停在列表总览。
    private(set) var fileIndex: Int?
    private(set) var selectedIndex: Int?
    private(set) var filterText = ""
    var isFilterFocused = false
    /// 视图重建时据此补一次 ⌘F 首次聚焦。
    private(set) var filterNeedsFocus = false
    private(set) var filterFocusRequestID = 0
    private(set) var filterBlurRequestID = 0
    private(set) var scrollRequest: GroupScrollRequest?
    private(set) var scrollRequestID = 0
    /// 组列表完整可见行范围。
    var visibleRowRange: ClosedRange<Int>?
    /// 复制反馈：下标 + 代际。
    private(set) var copyFeedbackIndex: Int?
    private(set) var copyFeedbackRevision = 0

    /// 单文件态是正在看的文件，列表态是选中的行；nil 时键盘动作按整条处理。
    var focusedFileIndex: Int? { fileIndex ?? selectedIndex }

    var isFilterActive: Bool {
        !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 预览停在组内列表。
    func isOverview(item: ClipboardItem?) -> Bool {
        guard let item, item.kind == .file, item.fileCount > 1 else { return false }
        return fileIndex == nil
    }

    func visibleIndices(item: ClipboardItem?, scopedURLs: [ScopedFileURL?]) -> [Int] {
        guard let item, item.kind == .file, item.fileCount > 1 else { return [] }
        let all = Array(0..<item.fileCount)
        guard isFilterActive else { return all }
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { matchesFilter(at: $0, query: query, item: item, scopedURLs: scopedURLs) }
    }

    private func matchesFilter(
        at index: Int,
        query: String,
        item: ClipboardItem,
        scopedURLs: [ScopedFileURL?]
    ) -> Bool {
        guard item.allFilePaths.indices.contains(index) else { return false }
        let path = resolvedPath(at: index, item: item, scopedURLs: scopedURLs)
        guard let path else { return false }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.localizedStandardContains(query) || path.localizedStandardContains(query)
    }

    /// 优先用 bookmark 解析后的路径，失联时回落到捕获路径。
    private func resolvedPath(at index: Int, item: ClipboardItem, scopedURLs: [ScopedFileURL?]) -> String? {
        guard item.allFilePaths.indices.contains(index) else { return nil }
        if scopedURLs.indices.contains(index), let url = scopedURLs[index] {
            return url.url.path
        }
        return item.allFilePaths[index]
    }

    /// 更新筛选词；选中行被筛掉时清空选中，并重新定位滚动。
    func setFilterText(_ text: String, item: ClipboardItem?, scopedURLs: [ScopedFileURL?]) {
        let previousVisible = visibleIndices(item: item, scopedURLs: scopedURLs)
        filterText = text
        let visible = visibleIndices(item: item, scopedURLs: scopedURLs)
        // 可见集变化后，旧范围不能再用。
        if visible != previousVisible {
            visibleRowRange = nil
        }
        if let selected = selectedIndex, !visible.contains(selected) {
            selectedIndex = nil
        }
        if let selected = selectedIndex {
            requestScroll(.row(selected))
        } else {
            requestScroll(.top)
        }
    }

    private func requestScroll(_ request: GroupScrollRequest) {
        scrollRequest = request
        scrollRequestID += 1
    }

    /// ⌘F 聚焦顶栏筛选框；视图重建时靠 `filterNeedsFocus` 补聚焦。
    func focusFilter() {
        filterNeedsFocus = true
        filterFocusRequestID += 1
    }

    /// 焦点落定后清掉待聚焦标记，避免下次重建再抢焦点。
    func filterFocusDidChange(_ focused: Bool) {
        isFilterFocused = focused
        filterNeedsFocus = false
    }

    func cancelFilter(item: ClipboardItem?, scopedURLs: [ScopedFileURL?]) {
        if filterText.isEmpty {
            dismissFilter()
        } else {
            setFilterText("", item: item, scopedURLs: scopedURLs)
        }
    }

    func dismissFilter() {
        filterBlurRequestID += 1
        isFilterFocused = false
        filterNeedsFocus = false
    }

    /// ↓ 进列表：已有选中保持不变，否则落到第一行。
    func moveFromFilterToList(item: ClipboardItem?, scopedURLs: [ScopedFileURL?]) {
        dismissFilter()
        if selectedIndex == nil {
            moveSelection(by: 1, visibleIndices: visibleIndices(item: item, scopedURLs: scopedURLs))
        }
    }

    func releaseFilterFocus() {
        isFilterFocused = false
        filterNeedsFocus = false
    }

    func showFile(_ index: Int) {
        fileIndex = index
        selectedIndex = index
        requestScroll(.row(index))
        if isFilterFocused || filterNeedsFocus {
            dismissFilter()
        }
    }

    func showOverview() {
        fileIndex = nil
        if let selected = selectedIndex {
            requestScroll(.row(selected))
        }
    }

    func selectFile(_ index: Int?) {
        selectedIndex = index
        if let index {
            requestScroll(.row(index))
        }
    }

    /// 触发某项的复制反馈。
    func markFileCopied(at index: Int) {
        copyFeedbackIndex = index
        copyFeedbackRevision &+= 1
    }

    /// 可见位置映射回组内原始下标。
    func fileIndex(atVisiblePosition position: Int, visibleIndices: [Int]) -> Int? {
        guard visibleIndices.indices.contains(position) else { return nil }
        return visibleIndices[position]
    }

    func canMoveSelection(by delta: Int, visibleIndices: [Int]) -> Bool {
        guard !visibleIndices.isEmpty, abs(delta) == 1 else { return false }
        guard let current = selectedIndex, let position = visibleIndices.firstIndex(of: current) else {
            return delta > 0
        }
        return visibleIndices.indices.contains(position + delta)
    }

    /// 列表态移动一行；返回 false 表示已到边界，不再切换外层历史。
    @discardableResult
    func moveSelection(by delta: Int, visibleIndices: [Int]) -> Bool {
        guard canMoveSelection(by: delta, visibleIndices: visibleIndices) else { return false }
        guard let current = selectedIndex, let position = visibleIndices.firstIndex(of: current) else {
            selectFile(visibleIndices[0])
            return true
        }
        selectFile(visibleIndices[position + delta])
        return true
    }

    @discardableResult
    func jumpSelection(toFirst: Bool, visibleIndices: [Int]) -> Bool {
        guard let target = toFirst ? visibleIndices.first : visibleIndices.last else { return false }
        guard selectedIndex != target else { return false }
        selectFile(target)
        return true
    }

    @discardableResult
    func stepFile(delta: Int, visibleIndices: [Int]) -> Bool {
        guard let current = fileIndex,
              let position = visibleIndices.firstIndex(of: current) else { return false }
        let target = position + delta
        guard visibleIndices.indices.contains(target) else { return false }
        showFile(visibleIndices[target])
        return true
    }

    @discardableResult
    func jumpFile(toFirst: Bool, visibleIndices: [Int]) -> Bool {
        guard let current = fileIndex, visibleIndices.contains(current),
              let target = toFirst ? visibleIndices.first : visibleIndices.last else { return false }
        guard target != current else { return false }
        showFile(target)
        return true
    }

    /// 单文件态在筛选结果里的位置（1-based）与总数；无筛选时为组内原始位置。
    func viewingPosition(item: ClipboardItem?, scopedURLs: [ScopedFileURL?]) -> (position: Int, total: Int)? {
        guard let current = fileIndex else { return nil }
        let visible = visibleIndices(item: item, scopedURLs: scopedURLs)
        guard let offset = visible.firstIndex(of: current) else { return nil }
        return (offset + 1, visible.count)
    }

    /// 关闭预览：清空组内会话；安全作用域访问由呈现状态负责释放。
    func reset() {
        fileIndex = nil
        selectedIndex = nil
        filterText = ""
        isFilterFocused = false
        filterNeedsFocus = false
        scrollRequest = nil
        scrollRequestID = 0
        visibleRowRange = nil
        copyFeedbackIndex = nil
    }
}
