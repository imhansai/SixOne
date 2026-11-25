//
//  ActiveFilterBar.swift
//  SixOne
//
//  顶栏分隔线与历史列表之间的筛选条：把当前生效的条件全部铺出来，
//  点 chip 移除，清除按钮一键复位。
//

import SwiftUI

struct ActiveFilterBar: View {
    let context: PanelContext

    private var store: HistoryListStore { context.store }
    private var searchState: SearchState { context.searchState }
    private var filterActions: FilterActionHandling? { context.filterActions }

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var scrollPosition = ScrollPosition(idType: String.self)

    private enum ActiveFilter: Identifiable {
        case kind(ClipboardItemKind)
        case source(String)
        case collection(UUID)
        case date(HistoryDateRange)

        var id: String {
            switch self {
            case .kind(let kind): "kind:\(kind.rawValue)"
            case .source(let bundleID): "source:\(bundleID)"
            case .collection(let id): "collection:\(id.uuidString)"
            case .date(let range): "date:\(range.rawValue)"
            }
        }
    }

    var body: some View {
        if !activeFilters.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(activeFilters) { filter in
                                chip(for: filter)
                            }
                        }
                        .padding(.vertical, 6)
                        .background {
                            HorizontalScrollBridge(
                                isEnabled: context.previewState.mode == .historyList,
                                onHorizontalScroll: { targetX in
                                    scrollPosition.scrollTo(x: targetX)
                                }
                            )
                        }
                    }
                    .scrollPosition($scrollPosition)
                    .onChange(of: activeFilters.count) { oldCount, newCount in
                        guard newCount > oldCount else { return }
                        // 新条件可能排在可视区外，滚到末尾让它露出来。
                        DispatchQueue.main.async {
                            scrollPosition.scrollTo(edge: .trailing)
                        }
                    }

                    clearButton
                }
                .padding(.horizontal, ClipboardLayout.headerHorizontalInset)
                PanelHairlineDivider()
            }
            .frame(height: ClipboardLayout.filterBarHeight)
        }
    }

    // MARK: - 条件推导

    private var activeFilters: [ActiveFilter] {
        let filter = store.filter
        var result: [ActiveFilter] = []
        for kind in ClipboardItemKind.allCases where filter.kinds.contains(kind) {
            result.append(.kind(kind))
        }
        let sourceNames = filter.sourceApps.map {
            ($0, context.caches.query.appDisplayName(for: $0))
        }
        for source in sourceNames.sorted(by: {
            $0.1.localizedStandardCompare($1.1) == .orderedAscending
        }) {
            result.append(.source(source.0))
        }
        for group in context.collections?.groups ?? [] where filter.collections.contains(group.id) {
            result.append(.collection(group.id))
        }
        for range in HistoryDateRange.allCases where filter.dateRanges.contains(range) {
            result.append(.date(range))
        }
        return result
    }

    // MARK: - Chip

    private func chip(for filter: ActiveFilter) -> some View {
        let title = title(for: filter)
        let appearance = FilterChipAppearance(
            isSelected: false,
            isIncreasedContrast: colorSchemeContrast == .increased
        )
        let button = Button {
            remove(filter)
        } label: {
            HStack(spacing: 5) {
                chipIcon(for: filter)
                    .frame(width: 13, height: 13)
                Text(title)
                    .font(.system(size: Self.chipFontSize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Self.chipTextWidth, alignment: .leading)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .foregroundStyle(appearance.foreground)
            .background(Capsule().fill(appearance.fill))
            .overlay(
                Capsule().strokeBorder(appearance.border, lineWidth: appearance.borderWidth)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(Localizer.string("Remove filter"))

        return Group {
            if FilterTextFit.isTruncated(
                title,
                maxWidth: Self.chipTextWidth,
                fontSize: Self.chipFontSize,
                weight: .medium
            ) {
                button.appTooltip(title)
            } else {
                button
            }
        }
    }

    /// 筛选条上 chip 文字的字体与最大宽度。
    private static let chipFontSize: CGFloat = 12.5
    private static let chipTextWidth: CGFloat = 180

    @ViewBuilder
    private func chipIcon(for filter: ActiveFilter) -> some View {
        switch filter {
        case .kind(let kind):
            Image(systemName: HistoryFilterPresentation.kindSymbol(kind))
                .font(.system(size: 12))
        case .source(let bundleID):
            if let icon = context.caches.appIcon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 12))
            }
        case .collection:
            Image(systemName: "folder")
                .font(.system(size: 12))
        case .date(let range):
            Image(systemName: HistoryFilterPresentation.dateSymbol(range))
                .font(.system(size: 12))
        }
    }

    private func title(for filter: ActiveFilter) -> String {
        switch filter {
        case .kind(let kind):
            HistoryFilterPresentation.kindTitle(kind)
        case .source(let bundleID):
            context.caches.query.appDisplayName(for: bundleID)
        case .collection(let id):
            context.collections?.group(id: id)?.name ?? Localizer.string("Group")
        case .date(let range):
            HistoryFilterPresentation.dateTitle(range)
        }
    }

    // MARK: - 动作

    private func remove(_ filter: ActiveFilter) {
        searchState.resignFocus()
        let next: HistoryFilter
        switch filter {
        case .kind(let kind):
            next = store.filter.toggled(kind: kind)
        case .source(let bundleID):
            next = store.filter.toggled(sourceApp: bundleID)
        case .collection(let id):
            next = store.filter.toggled(collectionID: id)
        case .date(let range):
            next = store.filter.toggled(dateRange: range)
        }
        filterActions?.panelDidRequestHistoryFilter(next)
    }

    private var clearButton: some View {
        let appearance = FilterChipAppearance(
            isSelected: false,
            isIncreasedContrast: colorSchemeContrast == .increased
        )
        return Button {
            searchState.resignFocus()
            filterActions?.panelDidRequestClearHistoryFilters()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                Text(Localizer.string("Clear Filters"))
                    .font(.system(size: 11.5, weight: .medium))
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .foregroundStyle(.secondary)
            .background(Capsule().fill(appearance.fill))
            .overlay(
                Capsule().strokeBorder(appearance.border, lineWidth: appearance.borderWidth)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Localizer.string("Clear Filters"))
    }
}
