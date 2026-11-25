//
//  HistoryFilterPopover.swift
//  SixOne
//
//  顶栏筛选按钮的系统 popover 内容：类型 / 来源 / 分组 / 日期四区，区内多选、区间组合。
//

import AppKit
import SwiftUI

struct HistoryFilterPopover: View {
    /// 内容高度上限；超出后在弹层内滚动。
    static let maximumContentHeight: CGFloat = 480

    let context: PanelContext

    private var store: HistoryListStore { context.store }
    private var actions: FilterActionHandling? { context.filterActions }
    private var groups: [CollectionRow] { context.collections?.groups ?? [] }
    /// 最近窗口的候选 + 已选来源；已选来源即使不在窗口里也要保留，保证可取消。
    private var sourceApps: [String] {
        FilterSourceListLayout.candidates(
            catalog: context.filterSources.bundleIdentifiers,
            selected: store.filter.sourceApps
        )
    }

    @State private var isShowingAllSources = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private enum Metrics {
        static let contentPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 12
        static let sectionTitleHeight: CGFloat = 13
        static let sectionTitleSpacing: CGFloat = 5
        static let chipWidth: CGFloat = 130
        static let chipHeight: CGFloat = 26
        static let chipHorizontalPadding: CGFloat = 8
        static let chipFontSize: CGFloat = 12
        static let chipIconSize: CGFloat = 14
        static let chipSpacing: CGFloat = 6
        static let gridSpacing: CGFloat = 6
        /// 常驻的滚动条通道，展开时列宽不跟着变。
        static let scrollbarLane: CGFloat = 16

        static var contentWidth: CGFloat {
            contentPadding * 2 + chipWidth * 3 + gridSpacing * 2 + scrollbarLane
        }

        /// chip 内文字可用宽度：列宽减左右内边距、图标与两侧间距。
        static var textWidth: CGFloat {
            chipWidth - chipHorizontalPadding * 2 - chipIconSize - chipSpacing * 2
        }
    }

    /// 固定列宽让内容有稳定宽度，高度超过上限后由 ScrollView 接管。
    private let columns = [
        GridItem(.fixed(Metrics.chipWidth), spacing: Metrics.gridSpacing),
        GridItem(.fixed(Metrics.chipWidth), spacing: Metrics.gridSpacing),
        GridItem(.fixed(Metrics.chipWidth), spacing: Metrics.gridSpacing),
    ]

    private var visibleSources: [String] {
        FilterSourceListLayout.visibleSources(
            sourceApps,
            selected: store.filter.sourceApps,
            isExpanded: isShowingAllSources
        )
    }

    private var showsMoreSourcesChip: Bool {
        isShowingAllSources
            || FilterSourceListLayout.hasMore(
                sourceApps,
                selected: store.filter.sourceApps,
                isExpanded: false
            )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content
        }
        .frame(width: Metrics.contentWidth)
        .frame(height: min(contentHeight, Self.maximumContentHeight))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Localizer.string("Filters"))
    }

    /// 与三列固定宽网格同步的内容高度；超过上限由 ScrollView 接管。
    private var contentHeight: CGFloat {
        var counts: [Int] = [ClipboardItemKind.allCases.count]
        if !sourceApps.isEmpty {
            counts.append(visibleSources.count + (showsMoreSourcesChip ? 1 : 0))
        }
        if !groups.isEmpty { counts.append(groups.count) }
        counts.append(HistoryDateRange.allCases.count)

        let sectionHeights = counts.map { count -> CGFloat in
            let rows = CGFloat((count + 2) / 3)
            return Metrics.sectionTitleHeight
                + Metrics.sectionTitleSpacing
                + rows * Metrics.chipHeight
                + (rows - 1) * Metrics.gridSpacing
        }
        return Metrics.contentPadding * 2
            + sectionHeights.reduce(0, +)
            + Metrics.sectionSpacing * CGFloat(counts.count - 1)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            section(title: Localizer.string("Type")) {
                ForEach(ClipboardItemKind.allCases, id: \.self) { kind in
                    chip(
                        title: HistoryFilterPresentation.kindTitle(kind),
                        isSelected: store.filter.kinds.contains(kind)
                    ) {
                        apply(store.filter.toggled(kind: kind))
                    } icon: {
                        Image(systemName: HistoryFilterPresentation.kindSymbol(kind))
                            .font(.system(size: 12.5))
                    }
                }
            }

            if !sourceApps.isEmpty {
                section(title: Localizer.string("Source App")) {
                    ForEach(visibleSources, id: \.self) { bundleIdentifier in
                        let displayName = context.caches.query.appDisplayName(
                            for: bundleIdentifier
                        )
                        chip(
                            title: displayName,
                            isSelected: store.filter.sourceApps.contains(bundleIdentifier),
                            tooltipText: displayName
                        ) {
                            apply(store.filter.toggled(sourceApp: bundleIdentifier))
                        } icon: {
                            appIcon(bundleIdentifier)
                        }
                    }
                    if showsMoreSourcesChip {
                        moreSourcesChip
                    }
                }
            }

            if !groups.isEmpty {
                section(title: Localizer.string("Group")) {
                    ForEach(groups) { group in
                        chip(
                            title: group.name,
                            isSelected: store.filter.collections.contains(group.id),
                            tooltipText: group.name
                        ) {
                            apply(store.filter.toggled(collectionID: group.id))
                        } icon: {
                            Image(systemName: "folder")
                                .font(.system(size: 12.5))
                        }
                    }
                }
            }

            section(title: Localizer.string("Date")) {
                ForEach(HistoryDateRange.allCases, id: \.self) { range in
                    chip(
                        title: HistoryFilterPresentation.dateTitle(range),
                        isSelected: store.filter.dateRanges.contains(range)
                    ) {
                        apply(store.filter.toggled(dateRange: range))
                    } icon: {
                        Image(systemName: HistoryFilterPresentation.dateSymbol(range))
                            .font(.system(size: 12.5))
                    }
                }
            }
        }
        .padding(Metrics.contentPadding)
    }

    private var moreSourcesChip: some View {
        chip(
            title: isShowingAllSources
                ? Localizer.string("Show Less")
                : Localizer.string("More"),
            isSelected: false
        ) {
            isShowingAllSources.toggle()
        } icon: {
            Image(systemName: isShowingAllSources ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sectionTitleSpacing) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: Metrics.sectionTitleHeight, alignment: .leading)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.gridSpacing) {
                content()
            }
        }
    }

    @ViewBuilder
    private func chip<Icon: View>(
        title: String,
        isSelected: Bool,
        tooltipText: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let appearance = FilterChipAppearance(
            isSelected: isSelected,
            isIncreasedContrast: colorSchemeContrast == .increased
        )
        let button = Button(action: action) {
            HStack(spacing: Metrics.chipSpacing) {
                icon()
                    .frame(width: Metrics.chipIconSize, height: Metrics.chipIconSize)
                Text(title)
                    .font(.system(
                        size: Metrics.chipFontSize,
                        weight: isSelected ? .semibold : .medium
                    ))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.chipHorizontalPadding)
            .frame(height: Metrics.chipHeight)
            .foregroundStyle(appearance.foreground)
            .background(Capsule().fill(appearance.fill))
            .overlay(
                Capsule().strokeBorder(appearance.border, lineWidth: appearance.borderWidth)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // 系统 popover 打开时会自动聚焦第一个按钮，不显示这圈焦点环。
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if let tooltipText,
           FilterTextFit.isTruncated(
               tooltipText,
               maxWidth: Metrics.textWidth,
               fontSize: Metrics.chipFontSize,
               weight: isSelected ? .semibold : .medium
           ) {
            button.appTooltip(tooltipText)
        } else {
            button
        }
    }

    @ViewBuilder
    private func appIcon(_ bundleIdentifier: String) -> some View {
        if let icon = context.caches.appIcon(for: bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app")
                .font(.system(size: 12))
        }
    }

    /// 点选只改筛选，不替用户关弹层；连续多选不用反复打开。
    private func apply(_ filter: HistoryFilter) {
        actions?.panelDidRequestHistoryFilter(filter)
    }
}

/// 来源很多时先露一屏；已选来源即使排在后面也要保持可见，方便直接取消。
nonisolated enum FilterSourceListLayout {
    /// 三列时 8 个来源 + 「更多」正好三整行，展开 / 收起不留下孤立格。
    static let collapsedLimit = 8

    static func visibleSources(
        _ sources: [String],
        selected: Set<String>,
        isExpanded: Bool,
        limit: Int = collapsedLimit
    ) -> [String] {
        guard !isExpanded, sources.count > limit else { return sources }
        let visible = Array(sources.prefix(limit))
        let visibleSet = Set(visible)
        return visible + sources.filter {
            selected.contains($0) && !visibleSet.contains($0)
        }
    }

    static func hasMore(
        _ sources: [String],
        selected: Set<String>,
        isExpanded: Bool,
        limit: Int = collapsedLimit
    ) -> Bool {
        !isExpanded
            && visibleSources(sources, selected: selected, isExpanded: false, limit: limit).count
                < sources.count
    }

    /// 候选 = 窗口内的来源 + 已选但不在窗口里的来源，后者排在末尾。
    static func candidates(catalog: [String], selected: Set<String>) -> [String] {
        let known = Set(catalog)
        return catalog + selected.subtracting(known).sorted()
    }
}
