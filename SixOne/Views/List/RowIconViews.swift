//
//  RowIconViews.swift
//  SixOne
//  行首图标与来源角标：历史列表与文件组列表共用。
//

import AppKit
import SwiftUI

enum RowIconMetrics {
    static let thumbnail: CGFloat = 40
    static let fileIcon: CGFloat = 38
    static let symbol: CGFloat = 44
    static let badge: CGFloat = 18
    static let badgeCorner: CGFloat = 4
    static let badgeOffset: CGFloat = 4
}

/// 文件类行首图标：缩略图 → 文件图标 → `doc` 符号。
struct RowFileIcon: View {
    let thumbnail: NSImage?
    let path: String?

    @Environment(PanelContext.self) private var context

    var body: some View {
        if let thumbnail {
            iconImage(thumbnail, size: RowIconMetrics.thumbnail)
        } else if let path, let icon = context.caches.fileIcon(for: path) {
            iconImage(icon, size: RowIconMetrics.fileIcon)
        } else {
            Image(systemName: "doc")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: RowIconMetrics.symbol, height: RowIconMetrics.symbol)
        }
    }

    private func iconImage(_ image: NSImage, size: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

/// 来源 App 角标；无 bundle id 或查不到 App 时不显示。
private struct RowSourceBadge: View {
    let bundleIdentifier: String?

    @Environment(PanelContext.self) private var context

    var body: some View {
        if let bundleIdentifier, let icon = context.caches.appIcon(for: bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: RowIconMetrics.badge, height: RowIconMetrics.badge)
                .clipShape(
                    RoundedRectangle(cornerRadius: RowIconMetrics.badgeCorner, style: .continuous)
                )
                .offset(x: RowIconMetrics.badgeOffset, y: RowIconMetrics.badgeOffset)
        }
    }
}

extension View {
    /// 叠加右下角来源角标。
    func rowSourceBadge(_ bundleIdentifier: String?) -> some View {
        overlay(alignment: .bottomTrailing) {
            RowSourceBadge(bundleIdentifier: bundleIdentifier)
        }
    }
}
