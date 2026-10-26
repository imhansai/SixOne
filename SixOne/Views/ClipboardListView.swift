//
//  ClipboardListView.swift
//  SixOne

import Foundation
import SwiftUI

/// Tahoe 风格剪贴板面板：搜索框 + 最近一窗历史列表（虚拟化 NSTableView）。
/// 行只存轻量快照，大字段按 id 惰性补齐；搜索走 DB 谓词，结果封顶 windowLimit 条。
struct ClipboardListView: View {
    let context: PanelContext

    private var store: HistoryListStore { context.store }
    private var manager: ClipboardManager { context.manager }
    private var searchState: SearchState { context.searchState }
    private var moreActionsState: MoreActionsState { context.moreActionsState }
    private var confirmationState: ConfirmationState { context.confirmationState }
    private var previewState: PreviewState { context.previewState }
    private var navigationState: NavigationState { context.navigationState }
    private var copyState: CopyState { context.copyState }
    private var noticeState: NoticeState { context.noticeState }
    private var actions: PanelActionHandler? { context.actions }

    @Environment(\.locale) private var locale
    @State private var noticeWork: DispatchWorkItem?
    /// 编辑保存后预览仍开：关闭时滚回顶部展示已置顶的条目。
    @State private var pendingTopFocusAfterEditedPreview = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                PanelHeaderChrome {
                    ClipboardTopBar(context: context)
                }
                content
                if store.hasOlder {
                    PanelHairlineDivider()
                    olderRecordsHint
                }
            }
            .opacity(previewState.item == nil ? 1 : 0)
            .allowsHitTesting(previewState.item == nil)

            if let item = previewState.item {
                PreviewDetailView(
                    item: item,
                    // 编辑落盘后条目已置顶，关闭预览时滚回顶部展示。
                    onItemEdited: { pendingTopFocusAfterEditedPreview = true },
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // 按 id 重建，避免切换条目时 @State 残留上一项。
                .id(item.id)
            }
        }
        .frame(width: ClipboardLayout.panelWidth, height: ClipboardLayout.panelHeight)
        .overlay(alignment: .top) {
            if let message = noticeState.message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(.regularMaterial)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .padding(.top, ClipboardLayout.headerHeight + 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: noticeState.message) { _, message in
            noticeWork?.cancel()
            guard let message, !message.isEmpty else { return }
            let work = DispatchWorkItem {
                withAnimation(.easeOut(duration: 0.25)) {
                    noticeState.message = nil
                }
            }
            noticeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + PanelTiming.notice, execute: work)
        }
        .onAppear {
            if store.rows.isEmpty {
                store.loadLatest()
            }
        }
        .onDisappear {
            noticeWork?.cancel()
            noticeWork = nil
            navigationState.clearPendingReveal()
            pendingTopFocusAfterEditedPreview = false
        }
        .onChange(of: copyState.itemID) { _, id in
            guard let id else { return }
            setCopiedFeedback(for: id)
        }
        .onChange(of: store.dataRevision) { _, _ in
            discardOrphanedSelection()
            discardDeletedPreview()
            revealTouchedItemIfNeeded()
        }
        .onChange(of: previewState.item?.id) { oldID, newID in
            if let newID {
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
        .onChange(of: store.didFailToLoad) { _, failed in
            // 有旧行时空态不显示，加载失败另发顶部提示。
            guard failed, !store.rows.isEmpty else { return }
            noticeState.message = Localizer.string("Could not load clipboard history.")
        }
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
        // context 由面板持有，闭包可直接捕获 self。
        Task {
            guard !(await store.itemExists(id: previewed)) else { return }
            // 等待期间用户可能已切到别的预览，只关仍停在已删除条目上的那个。
            guard previewState.item?.id == previewed else { return }
            previewState.close()
        }
    }

    // MARK: - 列表

    @ViewBuilder
    private var content: some View {
        if store.rows.isEmpty {
            if store.didFailToLoad {
                // 读库失败要说「读取失败」，不能说成空历史。
                emptyState(icon: "exclamationmark.triangle", text: "Could not load clipboard history.")
            } else if store.isSearching {
                emptyState(icon: "magnifyingglass", text: "No matches found")
            } else if store.isLoading, store.dataRevision == 0 {
                // 首次加载未落定：留白，避免闪出空历史文案。
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState(icon: "clipboard", text: "Recently copied content will appear here")
            }
        } else {
            rowList
        }
    }

    private var rowList: some View {
        HistoryListTableView(
            context: context,
            rows: store.rows,
            dataRevision: store.dataRevision,
            locale: locale,
            selectedItemID: navigationState.selectedItemID,
            isSelectionActive: navigationState.isSelectionActive,
            scrollRevision: navigationState.scrollRevision,
            isScrollBlocked: confirmationState.isPresenting,
            onSelect: { select(id: $0) },
            onActivate: { activate(id: $0) },
            onCopy: { flashCopied(id: $0) },
            menuProvider: { row, anchor in rowMenuBuilder.makeMenu(for: row, anchor: anchor) },
            onTopVisibleRowChanged: { first in
                navigationState.fullyVisibleFirstIndex = first
                store.noteTopVisibleIndex(first)
            },
            onScrollerLayoutChanged: { usesOverlayScrollers in
                // 行尾内缩跟随实际滚动条形态；写入可观察状态以触发行重建。
                context.scrollerLayout.usesOverlayScrollers = usesOverlayScrollers
            }
        )
    }

    /// 单击选中并请求带留白滚入视野（幂等）。
    private func select(id: UUID) {
        searchState.resignFocus()
        moreActionsState.resignFocus()
        navigationState.selectedItemID = id
        navigationState.isSelectionActive = true
        navigationState.requestScroll(toRow: id)
    }

    private func activate(id: UUID) {
        searchState.resignFocus()
        moreActionsState.resignFocus()
        actions?.panelDidActivate(id: id)
    }

    private func flashCopied(id: UUID) {
        manager.copy(id: id)
        setCopiedFeedback(for: id)
    }

    private func setCopiedFeedback(for id: UUID) {
        // 复制会触达置顶：等 store 落定后再滚进视野。
        navigationState.requestRevealAfterStoreChange(id: id)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            copyState.feedbackItemID = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PanelTiming.copiedFeedback) {
            if copyState.feedbackItemID == id {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    copyState.feedbackItemID = nil
                }
            }
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

    // MARK: - 行右键菜单

    private var rowMenuBuilder: RowMenuBuilder {
        RowMenuBuilder(
            manager: manager,
            panelActions: { actions },
            selectRow: { select(id: $0) },
            copyFeedback: { setCopiedFeedback(for: $0) },
            deleteRow: { delete(id: $0) }
        )
    }

    private func delete(id: UUID) {
        actions?.panelDidRequestDelete(id: id)
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

    private func emptyState(icon: String, text: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var olderRecordsHint: some View {
        Text(String(
            format: Localizer.string("Showing the latest %@ items. Search to find older ones."),
            "\(store.windowLimit)"
        ))
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}
