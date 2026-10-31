//
//  HistoryListCoordinator.swift
//  SixOne
//  列表会话协调：选中、预览关闭收尾、置顶揭示与复制反馈。
//

import SwiftUI

/// 列表视图只负责渲染；这些规则依赖 store / navigation / preview 的时序，放在这里可脱离视图测试。
@MainActor
final class HistoryListCoordinator {
    private let context: PanelContext
    private let store: HistoryListStore
    private let navigationState: NavigationState
    private let previewState: PreviewState
    private let copyState: CopyState
    private let searchState: SearchState
    private let moreActionsState: MoreActionsState

    /// 编辑保存后预览仍开：关闭时滚回顶部展示已置顶的条目。
    private var pendingTopFocusAfterEditedPreview = false
    /// 窗口外预览的存在性探测；同一 id 在途时不重复发。
    private var existenceProbeID: UUID?
    private var existenceProbeTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?

    init(context: PanelContext) {
        self.context = context
        self.store = context.store
        self.navigationState = context.navigationState
        self.previewState = context.previewState
        self.copyState = context.copyState
        self.searchState = context.searchState
        self.moreActionsState = context.moreActionsState
    }

    // MARK: - 列表动作

    /// 单击选中并请求带留白滚入视野（幂等）。
    func select(id: UUID) {
        searchState.resignFocus()
        moreActionsState.resignFocus()
        navigationState.selectedItemID = id
        navigationState.isSelectionActive = true
        navigationState.requestScroll(toRow: id)
    }

    func activate(id: UUID, asPlainText: Bool) {
        searchState.resignFocus()
        moreActionsState.resignFocus()
        context.actions?.panelDidActivate(id: id, asPlainText: asPlainText)
    }

    func requestDelete(id: UUID) {
        context.actions?.panelDidRequestDelete(id: id)
    }

    func noteVisibleRowRange(_ range: ClosedRange<Int>) {
        navigationState.fullyVisibleRange = range
        navigationState.fullyVisibleFirstIndex = range.lowerBound
        store.noteTopVisibleIndex(range.lowerBound)
    }

    // MARK: - 复制反馈

    func copyWithFeedback(id: UUID) {
        context.copyItem(id: id)
        setCopiedFeedback(for: id)
    }

    func setCopiedFeedback(for id: UUID) {
        // 复制会触达置顶：等 store 落定后再滚进视野。
        navigationState.requestRevealAfterStoreChange(id: id)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            copyState.feedbackItemID = id
        }
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(PanelTiming.copiedFeedback))
            guard !Task.isCancelled,
                  let self,
                  self.copyState.feedbackItemID == id else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.copyState.feedbackItemID = nil
            }
        }
    }

    // MARK: - 数据变化

    func handleDataRevisionChange() {
        discardOrphanedSelection()
        discardDeletedPreview()
        revealTouchedItemIfNeeded()
    }

    /// 选中行已不在窗口内时摘掉选中，避免键盘导航复用失效锚点。
    private func discardOrphanedSelection() {
        guard let selected = navigationState.selectedItemID,
              !store.rows.contains(where: { $0.id == selected }) else { return }
        clearSelection()
    }

    /// 预览条目已被删除：关掉预览，正文与文件授权均已失效。
    private func discardDeletedPreview() {
        guard let previewed = previewState.item?.id else { return }
        // 还在窗口内就必然在库里，省一次探测。
        guard !store.rows.contains(where: { $0.id == previewed }) else { return }
        // 同一 id 的探测在途时不重复发；缩略图批量更新会连续触发 dataRevision。
        guard existenceProbeID != previewed else { return }
        existenceProbeTask?.cancel()
        existenceProbeID = previewed
        existenceProbeTask = Task { [weak self] in
            guard let self else { return }
            let exists = await self.store.itemExists(id: previewed)
            guard !Task.isCancelled else { return }
            self.existenceProbeID = nil
            guard !exists else { return }
            // 等待期间用户可能已切到别的预览，只关仍停在已删除条目上的那个。
            guard self.previewState.item?.id == previewed else { return }
            self.previewState.close()
        }
    }

    /// 置顶条目到达第 0 行后再揭示；已离开窗口则放弃。
    private func revealTouchedItemIfNeeded() {
        guard let pending = navigationState.pendingRevealItemID else { return }
        if store.rows.first?.id == pending {
            navigationState.clearPendingReveal()
            navigationState.requestScroll(toRow: pending)
        } else if !store.rows.contains(where: { $0.id == pending }) {
            navigationState.clearPendingReveal()
        }
    }

    // MARK: - 预览关闭

    func markPreviewEdited() {
        pendingTopFocusAfterEditedPreview = true
    }

    func handlePreviewIDChange(from oldID: UUID?, to newID: UUID?) {
        if newID != nil {
            // 切换条目后关闭不应回滚到第 0 行。
            if let oldID, newID != oldID {
                pendingTopFocusAfterEditedPreview = false
            }
            return
        }
        if let oldID {
            handlePreviewClosed(id: oldID)
        }
    }

    /// 预览关闭后收尾：编辑保存过的条目滚回顶部；已不在结果中则清选中并回顶部。
    private func handlePreviewClosed(id: UUID) {
        let shouldFocusTop = pendingTopFocusAfterEditedPreview
        pendingTopFocusAfterEditedPreview = false

        if store.rows.contains(where: { $0.id == id }) {
            if shouldFocusTop {
                navigationState.requestScroll(toRow: id)
            }
            return
        }

        clearSelection()
        navigationState.requestScrollToTop()
    }

    private func clearSelection() {
        navigationState.selectedItemID = nil
        navigationState.isSelectionActive = false
    }

    // MARK: - 收尾

    func stop() {
        existenceProbeTask?.cancel()
        existenceProbeTask = nil
        existenceProbeID = nil
        navigationState.clearPendingReveal()
        pendingTopFocusAfterEditedPreview = false
    }
}
