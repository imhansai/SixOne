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

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// 筛选条滚动位置；滚轮、滚到底与排序拖拽共用同一份状态。
    @State private var scrollPosition = ScrollPosition(idType: CollectionRow.ID.self)
    /// 分组拖拽会话是否活跃；驱动边缘自动滚动与面板保持。
    @State private var isDraggingGroup = false
    /// 正在拖拽的分组；原位置隐藏，留给系统占位。
    @State private var draggedGroupIDs: Set<CollectionRow.ID> = []

    /// 选中态用填充、边框、字重区分，不只靠色相。
    private struct ChipStyle {
        let fill: Color
        let border: Color
        let borderWidth: CGFloat
        let text: Color
        let weight: Font.Weight
    }

    var body: some View {
        if let groups = context.collections?.groups, !groups.isEmpty {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(groups) { group in
                            chip(group)
                        }
                        .reorderable()
                    }
                    .padding(.vertical, 6)
                    .reorderContainer(for: CollectionRow.self) { difference in
                        reorderGroups(by: difference)
                    }
                    // 滚轮桥挂在排序容器外，别把额外 NSView 塞进去。
                    .background {
                        HorizontalScrollBridge(
                            isEnabled: context.previewState.mode == .historyList,
                            onHorizontalScroll: { targetX in
                                scrollPosition.scrollTo(x: targetX)
                            },
                            isDragging: isDraggingGroup
                        )
                    }
                }
                .scrollPosition($scrollPosition)
                .onDragSessionUpdated(updateDragSession)
                .onDisappear {
                    // 视图先于会话结束移除时兜底。
                    resetDragSession()
                }
                // 左右留白放在滚动容器外：滚动时 chip 也不会贴到面板边缘。
                .padding(.horizontal, ClipboardLayout.headerHorizontalInset)
                .onChange(of: groups) { oldGroups, newGroups in
                    scrollToNewestGroup(oldGroups, newGroups)
                }
                .onChange(of: context.panelState.isVisible) { _, isVisible in
                    // 收起后收不到会话更新。
                    if !isVisible { resetDragSession() }
                }
                PanelHairlineDivider()
            }
            .frame(height: ClipboardLayout.collectionFilterBarHeight)
        }
    }

    /// 跟官方 `DragSession` 走：活跃时隐藏源 chip、允许边缘滚动并挡住面板收起。
    private func updateDragSession(_ session: DragSession) {
        switch session.phase {
        case .initial, .active:
            updateDragState(
                dragging: true,
                ids: session.draggedItemIDs(for: CollectionRow.ID.self)
            )
        default:
            resetDragSession()
        }
    }

    /// 会话结束 / 视图消失 / 面板收起统一收尾。
    private func resetDragSession() {
        updateDragState(dragging: false, ids: [])
    }

    private func updateDragState(dragging: Bool, ids: [CollectionRow.ID]) {
        setDragging(dragging)
        let next = dragging ? Set(ids) : []
        if next != draggedGroupIDs { draggedGroupIDs = next }
    }

    private func setDragging(_ dragging: Bool) {
        if dragging != isDraggingGroup { isDraggingGroup = dragging }
        // 无条件回写，状态分叉时也能复位。
        context.collectionDragState.isDragging = dragging
    }

    /// 末尾追加分组后滚到底；首次加载、重命名、排序不动。
    private func scrollToNewestGroup(
        _ oldGroups: [CollectionRow],
        _ newGroups: [CollectionRow]
    ) {
        guard !oldGroups.isEmpty,
              newGroups.count > oldGroups.count,
              newGroups.starts(with: oldGroups)
        else { return }
        // 新 chip 的布局可能还没落定，推迟一轮再滚到底。
        DispatchQueue.main.async {
            scrollPosition.scrollTo(edge: .trailing)
        }
    }

    /// 再点已选中的分组就取消筛选、回到全部数据。
    private func chip(_ group: CollectionRow) -> some View {
        let isSelected = store.collectionFilter == .collection(group.id)
        let style = chipStyle(isSelected: isSelected)
        return Button {
            searchState.resignFocus()
            actions?.panelDidRequestCollectionFilter(
                store.collectionFilter.toggled(group.id)
            )
        } label: {
            Text(group.name)
                .font(.system(size: 12.5, weight: style.weight))
                .lineLimit(1)
                .truncationMode(.tail)
                // 40 字的分组名最多占 180pt 文本宽，余下留给其他 chip。
                .frame(maxWidth: 180, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .foregroundStyle(style.text)
                .background(Capsule().fill(style.fill))
                .overlay(
                    Capsule().strokeBorder(style.border, lineWidth: style.borderWidth)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(draggedGroupIDs.contains(group.id) ? 0 : 1)
        .appTooltip(group.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button {
                searchState.resignFocus()
                actions?.panelDidRequestRenameCollection(id: group.id)
            } label: {
                Label(Localizer.string("Rename Group…"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                searchState.resignFocus()
                actions?.panelDidRequestDeleteCollection(id: group.id)
            } label: {
                Label(Localizer.string("Delete Group…"), systemImage: "trash")
            }
        }
    }

    /// 落位交给控制器：先改内存顺序，再延迟写库。
    private func reorderGroups(
        by difference: ReorderDifference<CollectionRow.ID, ReorderableSingleCollectionIdentifier>
    ) {
        let targetID: UUID?
        switch difference.destination.position {
        case .before(let id): targetID = id
        case .end: targetID = nil
        }
        actions?.panelDidRequestReorderCollections(
            movingIDs: difference.sources,
            before: targetID
        )
    }

    private var neutralFillOpacity: Double {
        colorSchemeContrast == .increased ? 0.07 : 0.045
    }

    private var neutralBorderOpacity: Double {
        colorSchemeContrast == .increased ? 0.16 : 0.08
    }

    private func chipStyle(isSelected: Bool) -> ChipStyle {
        let isIncreased = colorSchemeContrast == .increased
        if isSelected {
            return ChipStyle(
                fill: PanelSelectionAppearance.active.opacity(isIncreased ? 0.30 : 0.22),
                border: PanelSelectionAppearance.active,
                borderWidth: isIncreased ? 2 : 1.5,
                text: .primary,
                weight: .semibold
            )
        }
        return ChipStyle(
            fill: Color.primary.opacity(neutralFillOpacity),
            border: Color.primary.opacity(neutralBorderOpacity),
            borderWidth: 1,
            text: Color.primary.opacity(isIncreased ? 0.85 : 0.72),
            weight: .medium
        )
    }
}
