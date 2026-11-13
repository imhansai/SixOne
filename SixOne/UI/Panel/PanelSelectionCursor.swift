//
//  PanelSelectionCursor.swift
//  SixOne
//  列表选中游标与「预览跟着选中走」；选中状态只有 NavigationState.selectedItemID 一份。

import Foundation

final class PanelSelectionCursor {
    private let store: HistoryListStore
    private let navigationState: NavigationState
    private let previewState: PreviewState
    private let previewLauncher: PreviewLauncher

    var selectedItemID: UUID? {
        get { navigationState.selectedItemID }
        set { navigationState.selectedItemID = newValue }
    }

    init(
        store: HistoryListStore,
        navigationState: NavigationState,
        previewState: PreviewState,
        previewLauncher: PreviewLauncher
    ) {
        self.store = store
        self.navigationState = navigationState
        self.previewState = previewState
        self.previewLauncher = previewLauncher
    }

    // MARK: - 在列表里移动

    /// 键盘 ↑/↓ 移动选中项并同步高亮与滚动，到边界停住。
    func move(direction: Int, then: (() -> Void)? = nil) {
        let rows = store.rows
        guard !rows.isEmpty else {
            store.loadLatest()
            then?()
            return
        }
        let currentIndex = selectedItemID.flatMap { id in
            rows.firstIndex(where: { $0.id == id })
        }
        guard let currentIndex else {
            // 尚未选中：↓ 落最新一条，↑ 不动。
            if direction > 0 {
                move(to: 0)
            }
            then?()
            return
        }
        let target = currentIndex + direction
        move(to: min(max(target, 0), rows.count - 1))
        then?()
    }

    /// 选中指定下标的条目并滚进视野。
    /// 同一条目重复选中时普通步进不再滚动（避免闪滚动条）；端点跳转仍要记一次，好播提示音。
    func move(to index: Int, isEndpointJump: Bool = false) {
        let rows = store.rows
        guard index >= 0, index < rows.count else { return }
        let row = rows[index]
        if selectedItemID == row.id {
            // 重复写同值会触发 SwiftUI 重新求值，按住方向键时高亮会闪。
            if !navigationState.isSelectionActive {
                navigationState.isSelectionActive = true
            }
            if isEndpointJump {
                navigationState.requestScroll(
                    toRow: row.id,
                    isEndpointJump: true,
                    isSelectionAlreadyAtEndpoint: true
                )
            }
            return
        }
        selectedItemID = row.id
        navigationState.isSelectionActive = true
        navigationState.requestScroll(
            toRow: row.id,
            isEndpointJump: isEndpointJump,
            isSelectionAlreadyAtEndpoint: false
        )
    }

    func jumpToBeginning(then: (() -> Void)? = nil) {
        guard !store.rows.isEmpty else {
            store.loadLatest()
            then?()
            return
        }
        move(to: 0, isEndpointJump: true)
        then?()
    }

    func jumpToOldest(then: (() -> Void)? = nil) {
        guard !store.rows.isEmpty else {
            store.loadLatest()
            then?()
            return
        }
        move(to: store.rows.count - 1, isEndpointJump: true)
        then?()
    }

    // MARK: - 预览跟着选中走

    /// 预览内 ↑/↓：以当前预览项为锚移动选中，再切预览。
    func stepPreview(direction: Int) {
        // 锚失效（预览期间窗口重载）时忽略，避免 move 跳到首/末行。
        guard let anchor = previewState.item?.id,
              store.rows.contains(where: { $0.id == anchor }) else { return }
        selectedItemID = anchor
        move(direction: direction) { [weak self] in
            self?.switchPreviewAfterMove(from: anchor)
        }
    }

    func jumpPreview(to index: Int) {
        guard let anchor = previewState.item?.id,
              store.rows.contains(where: { $0.id == anchor }) else { return }
        selectedItemID = anchor
        move(to: index)
        switchPreviewAfterMove(from: anchor)
    }

    func jumpPreviewToOldest() {
        guard let anchor = previewState.item?.id,
              store.rows.contains(where: { $0.id == anchor }) else { return }
        selectedItemID = anchor
        jumpToOldest { [weak self] in
            self?.switchPreviewAfterMove(from: anchor)
        }
    }

    private func switchPreviewAfterMove(from anchorID: UUID) {
        guard let newID = selectedItemID, newID != anchorID else { return }
        switchPreview(id: newID, rollbackTo: anchorID)
    }

    /// 切换预览；失败时回滚选中与滚动，避免「看到 A、选中 B」。
    private func switchPreview(id: UUID, rollbackTo anchorID: UUID) {
        if previewLauncher.presentIfPossible(id: id) { return }
        guard store.rows.contains(where: { $0.id == anchorID }) else { return }
        selectedItemID = anchorID
        navigationState.requestScroll(toRow: anchorID)
    }
}
