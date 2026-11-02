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
    private var confirmationState: ConfirmationState { context.confirmationState }
    private var previewState: PreviewState { context.previewState }
    private var navigationState: NavigationState { context.navigationState }
    private var copyState: CopyState { context.copyState }
    private var noticeState: NoticeState { context.noticeState }
    private var actions: ItemActionHandling? { context.itemActions }

    @Environment(\.locale) private var locale
    @State private var noticeFeedback = TransientFeedback()
    @State private var coordinator: HistoryListCoordinator

    init(context: PanelContext) {
        self.context = context
        _coordinator = State(initialValue: HistoryListCoordinator(context: context))
    }

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
                    context: context,
                    // 编辑落盘后条目已置顶，关闭预览时滚回顶部展示。
                    onItemEdited: { coordinator.markPreviewEdited() },
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
            noticeFeedback.cancel()
            guard let message, !message.isEmpty else { return }
            noticeFeedback.schedule(after: PanelTiming.notice) {
                withAnimation(.easeOut(duration: 0.25)) {
                    noticeState.message = nil
                }
            }
        }
        .onAppear {
            if store.rows.isEmpty {
                store.loadLatest()
            }
        }
        .onDisappear {
            noticeFeedback.cancel()
            coordinator.stop()
        }
        .onChange(of: copyState.itemID) { _, id in
            guard let id else { return }
            coordinator.setCopiedFeedback(for: id)
        }
        .onChange(of: store.dataRevision) { _, _ in
            coordinator.handleDataRevisionChange()
        }
        .onChange(of: previewState.item?.id) { oldID, newID in
            coordinator.handlePreviewIDChange(from: oldID, to: newID)
        }
        .onChange(of: store.didFailToLoad) { _, failed in
            // 有旧行时空态不显示，加载失败另发顶部提示。
            guard failed, !store.rows.isEmpty else { return }
            noticeState.message = Localizer.string("Could not load clipboard history.")
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

    /// 按住 ⌘ 才读取可见范围，平时滚动不额外触发列表更新。
    private var quickPasteRange: ClosedRange<Int>? {
        guard context.quickPasteHintState.isShowing else { return nil }
        return navigationState.fullyVisibleRange
    }

    private var rowList: some View {
        HistoryListTableView(
            context: context,
            rows: store.rows,
            dataRevision: store.dataRevision,
            locale: locale,
            selectedItemID: navigationState.selectedItemID,
            copiedItemID: copyState.feedbackItemID,
            isSelectionActive: navigationState.isSelectionActive,
            scrollRevision: navigationState.scrollRevision,
            isScrollBlocked: confirmationState.isPresenting,
            quickPasteRange: quickPasteRange,
            onSelect: { coordinator.select(id: $0) },
            onActivate: { coordinator.activate(id: $0, asPlainText: $1) },
            onCopy: { coordinator.copyWithFeedback(id: $0) },
            menuProvider: { row, anchor in rowMenuBuilder.makeMenu(for: row, anchor: anchor) },
            onVisibleRowRangeChanged: { coordinator.noteVisibleRowRange($0) },
            onScrollerLayoutChanged: { usesOverlayScrollers in
                // 行尾内缩跟随实际滚动条形态；写入可观察状态以触发行重建。
                context.scrollerLayout.usesOverlayScrollers = usesOverlayScrollers
            }
        )
    }

    // MARK: - 行右键菜单

    private var rowMenuBuilder: RowMenuBuilder {
        RowMenuBuilder(
            manager: manager,
            panelActions: { actions },
            selectRow: { coordinator.select(id: $0) },
            copyFeedback: { coordinator.setCopiedFeedback(for: $0) },
            copyItem: { context.copyItem(id: $0) },
            copyItemAsPlainText: { context.copyItemAsPlainText(id: $0) },
            deleteRow: { coordinator.requestDelete(id: $0) }
        )
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
