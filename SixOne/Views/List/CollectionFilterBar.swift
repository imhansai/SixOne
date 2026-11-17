//
//  CollectionFilterBar.swift
//  SixOne
//
//  顶栏分隔线与历史列表之间的分组筛选条；没有分组时整条不显示。
//

import SwiftUI

struct CollectionFilterBar: View {
    let context: PanelContext

    private var store: HistoryListStore { context.store }
    private var searchState: SearchState { context.searchState }
    private var actions: CollectionActionHandling? { context.collectionActions }

    var body: some View {
        if let groups = context.collections?.groups, !groups.isEmpty {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip(.all, title: Localizer.string("All"))
                        chip(.ungrouped, title: Localizer.string("Ungrouped"))
                        ForEach(groups) { group in
                            chip(.collection(group.id), title: group.name)
                        }
                        newGroupButton
                    }
                    .padding(.horizontal, ClipboardLayout.headerHorizontalInset)
                    .padding(.vertical, 6)
                }
                PanelHairlineDivider()
            }
            .frame(height: ClipboardLayout.collectionFilterBarHeight)
        }
    }

    @ViewBuilder
    private func chip(_ filter: CollectionFilter, title: String) -> some View {
        let isSelected = store.collectionFilter == filter
        let button = Button {
            searchState.resignFocus()
            actions?.panelDidRequestCollectionFilter(filter)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .background(
                    Capsule().fill(
                        isSelected
                            ? Color.accentColor.opacity(0.18)
                            : Color.primary.opacity(0.06)
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if case .collection(let id) = filter {
            button.contextMenu {
                Button {
                    searchState.resignFocus()
                    actions?.panelDidRequestRenameCollection(id: id)
                } label: {
                    Label(Localizer.string("Rename Group…"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    searchState.resignFocus()
                    actions?.panelDidRequestDeleteCollection(id: id)
                } label: {
                    Label(Localizer.string("Delete Group…"), systemImage: "trash")
                }
            }
        } else {
            button
        }
    }

    private var newGroupButton: some View {
        Button {
            searchState.resignFocus()
            actions?.panelDidRequestNewCollection()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .appTooltip(Localizer.string("New Group…"))
        .accessibilityLabel(Localizer.string("New Group…"))
    }
}
