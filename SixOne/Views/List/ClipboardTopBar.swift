//
//  ClipboardTopBar.swift
//  SixOne
//
//  剪贴板面板顶栏：装饰图标 + 原生搜索框 + 筛选按钮 + 「更多操作」菜单。
//

import SwiftUI

struct ClipboardTopBar: View {
    let context: PanelContext

    private var panelState: PanelState { context.panelState }
    private var searchState: SearchState { context.searchState }
    private var moreActionsState: MoreActionsState { context.moreActionsState }
    private var filterState: FilterState { context.filterState }
    private var navigationState: NavigationState { context.navigationState }
    private var searchSession: PanelSearchSession { context.searchSession }
    private var searchActions: SearchActionHandling? { context.searchActions }
    private var collectionActions: CollectionActionHandling? { context.collectionActions }
    private var shellActions: ShellActionHandling? { context.shellActions }
    private var store: HistoryListStore { context.store }

    @FocusState private var isMoreActionsFocused: Bool
    @FocusState private var isFilterFocused: Bool

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

            filterButton

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
            // 搜索框获得焦点时保留列表选中并让出菜单站，Tab/↑↓ 可复用原选中项。
            if focused {
                moreActionsState.resignFocus()
                filterState.resignFocus()
                filterState.dismiss()
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
            placeholder: searchPlaceholder,
            focusRequestID: searchState.focusRequestID,
            blurRequestID: searchState.blurRequestID,
            resignOnOutsideClick: true,
            onTextChange: { newText in
                searchState.text = newText
            },
            onFocusChange: { focused in
                guard searchState.isFocused != focused else { return }
                searchState.isFocused = focused
            },
            onCancel: { [weak searchActions] in
                searchActions?.panelDidRequestSearchCancel()
            },
            onMoveDown: { [weak searchActions] in
                searchActions?.panelDidRequestSearchMoveDown()
            },
            onTab: { [weak searchActions] backwards in
                searchActions?.panelDidRequestSearchTab(backwards: backwards)
            }
        )
    }

    private var searchPlaceholder: String {
        guard let title = selectedCollectionTitle else {
            return Localizer.string("Search Clipboard")
        }
        return String(format: Localizer.string("Search in %@"), title)
    }

    /// 仅选中一个分组时用于搜索占位；多选或未选时回落默认文案。
    private var selectedCollectionTitle: String? {
        guard store.filter.collections.count == 1,
              let id = store.filter.collections.first
        else { return nil }
        return context.collections?.group(id: id)?.name ?? Localizer.string("Group")
    }

    // MARK: - 筛选

    /// 有任一筛选生效时用实心图标，避免收起的弹层让用户忘了筛选还在。
    private var filterButton: some View {
        Button {
            filterState.toggle()
        } label: {
            Image(
                systemName: store.filter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(store.filter.isActive ? Color.accentColor : Color.secondary)
            .contentShape(.focusEffect, Circle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .appTooltip(Localizer.string("Filters"))
        .accessibilityLabel(Localizer.string("Filters"))
        .accessibilityAddTraits(filterState.isPresented ? .isSelected : [])
        .focused($isFilterFocused)
        .onChange(of: filterState.focusRequestID) { isFilterFocused = true }
        .onChange(of: isFilterFocused) { _, focused in
            guard filterState.isFocused != focused else { return }
            filterState.isFocused = focused
        }
        .onChange(of: filterState.isFocused) { _, focused in
            guard !focused, isFilterFocused else { return }
            isFilterFocused = false
        }
        .popover(
            isPresented: Binding(
                get: { filterState.isPresented },
                set: { presented in
                    guard !presented, filterState.isPresented else { return }
                    filterState.dismiss()
                    shellActions?.panelDidDismissFilterPopover()
                }
            ),
            arrowEdge: .top
        ) {
            HistoryFilterPopover(context: context)
        }
    }

    // MARK: - 更多操作

    private var moreActionsMenu: some View {
        Menu {
            if let collections = context.collections {
                groupsMenu(collections)
                Divider()
            }

            Button {
                shellActions?.panelDidRequestClearHistory()
            } label: {
                Label(Localizer.string("Clear History"), systemImage: "trash")
            }

            if shellActions?.canRequestSettings == true {
                Divider()
                Button {
                    shellActions?.panelDidRequestSettings()
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

    /// 分组管理放在「更多操作」：新建、按组重命名 / 删除。
    private func groupsMenu(_ collections: CollectionListStore) -> some View {
        Menu {
            Button {
                collectionActions?.panelDidRequestCreateCollection()
            } label: {
                Label(Localizer.string("New Group…"), systemImage: "folder.badge.plus")
            }

            if !collections.groups.isEmpty {
                Divider()
                ForEach(collections.groups) { group in
                    Menu(group.name) {
                        Button {
                            collectionActions?.panelDidRequestRenameCollection(id: group.id)
                        } label: {
                            Label(Localizer.string("Rename Group…"), systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            collectionActions?.panelDidRequestDeleteCollection(id: group.id)
                        } label: {
                            Label(Localizer.string("Delete Group…"), systemImage: "trash")
                        }
                    }
                }
            }
        } label: {
            Label(Localizer.string("Groups"), systemImage: "folder")
        }
    }
}
