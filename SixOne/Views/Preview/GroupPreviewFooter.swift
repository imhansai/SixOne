//
//  GroupPreviewFooter.swift
//  SixOne
//  文件组总览底部信息条：有别名显示别名，无别名显示时间，均居中；tooltip 分行。
//

import SwiftUI

struct GroupPreviewFooter: View {
    let item: ClipboardItem
    let meta: PreviewGroupMeta?

    var body: some View {
        PanelFooterHint {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(visibleLine)
                    .lineLimit(1)
                    .fixedSize()
                    .textSelection(.enabled)
                    .frame(minWidth: ClipboardLayout.previewContentWidth, alignment: .center)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ClipboardLayout.previewInset)
            .appTooltip(tooltip)
        }
    }

    /// 别名在前，时间信息随后。
    private var visibleLine: String {
        ([aliasSegment] + timeSegments).compactMap { $0 }.joined(separator: " · ")
    }

    private var tooltip: String {
        var parts = timeSegments
        if let aliasSegment { parts.insert(aliasSegment, at: 0) }
        return parts.joined(separator: "\n")
    }

    private var aliasSegment: String? {
        AliasNormalizer.displayable(item.alias).map {
            String(format: Localizer.string("Alias: %@"), $0)
        }
    }

    private var timeSegments: [String] {
        var parts: [String] = []
        if let modDate = meta?.latestModDate {
            parts.append(PreviewSubtitle.lastModifiedLabel(modDate))
        }
        parts.append(PreviewSubtitle.firstRecordedTimeLabel(item.firstCapturedAt))
        parts.append(PreviewSubtitle.lastCopiedTimeLabel(item.lastActivityAt))
        return parts
    }
}
