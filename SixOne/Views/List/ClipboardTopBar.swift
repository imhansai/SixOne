//
//  ClipboardTopBar.swift
//  SixOne
//
//  剪贴板面板顶栏：装饰图标 + 原生搜索框 + 「更多操作」菜单。
//

import SwiftUI

struct ClipboardTopBar: View {
    let context: PanelContext

    private var panelState: PanelState { context.panelState }
    private var searchState: SearchState { context.searchState }
    private var moreActionsState: MoreActionsState { context.moreActionsState }
    private var navigationState: NavigationState { context.navigationState }
    private var searchSession: PanelSearchSession { context.searchSession }
    private var actions: PanelActionHandler? { context.actions }

    @FocusState private var isMoreActionsFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(width: 44, height: 44)
            .allowsHitTesting(false)

            searchField
                .frame(maxWidth: .infinity)

            moreActionsMenu
        }
        .onChange(of: panelState.isVisible) { _, visible in
            guard visible else { return }
            searchSession.syncToStore()
        }
        .onChange(of: searchState.text) { _, _ in
            searchSession.textDidChange()
        }
        .onChange(of: searchState.isFocused) { _, focused in
            // 搜索框获得焦点时保留列表选中并让出更多操作站，Tab/↑↓ 可复用原选中项。
            if focused {
                moreActionsState.resignFocus()
                navigationState.isSelectionActive = false
            }
        }
        .onDisappear {
            searchSession.cancelPendingWork()
        }
    }

    // MARK: - 搜索栏

    /// 原生文本框（无放大镜/清除按钮/边框背景），清空走 Esc。
    private var searchField: some View {
        SearchField(
            text: searchState.text,
            placeholder: Localizer.string("Search Clipboard"),
            focusRequestID: searchState.focusRequestID,
            blurRequestID: searchState.blurRequestID,
            onTextChange: { newText in
                searchState.text = newText
            },
            onFocusChange: { focused in
                guard searchState.isFocused != focused else { return }
                searchState.isFocused = focused
            },
            onCancel: { [weak actions] in
                actions?.panelDidRequestSearchCancel()
            },
            onMoveDown: { [weak actions] in
                actions?.panelDidRequestSearchMoveDown()
            },
            onTab: { [weak actions] backwards in
                actions?.panelDidRequestSearchTab(backwards: backwards)
            }
        )
    }

    // MARK: - 更多操作

    private var moreActionsMenu: some View {
        Menu {
            Button {
                actions?.panelDidRequestClearHistory()
            } label: {
                Label(Localizer.string("Clear History"), systemImage: "trash")
            }

            if actions?.canRequestSettings == true {
                Button {
                    actions?.panelDidRequestSettings()
                } label: {
                    Label(Localizer.string("Open Settings"), systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(.focusEffect, Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .appTooltip(Localizer.string("More Actions"))
        .accessibilityLabel(Localizer.string("More Actions"))
        .focused($isMoreActionsFocused)
        .onChange(of: moreActionsState.focusRequestID) { isMoreActionsFocused = true }
        .onChange(of: isMoreActionsFocused) { _, focused in
            guard moreActionsState.isFocused != focused else { return }
            moreActionsState.isFocused = focused
        }
        .onChange(of: moreActionsState.isFocused) { _, focused in
            guard !focused, isMoreActionsFocused else { return }
            isMoreActionsFocused = false
        }
    }
}
