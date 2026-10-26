//
//  AccessibilityPermissionSection.swift
//  SixOne
//
//  通用设置页里的「辅助功能权限」小节：展示授权状态并提供一键申请入口。
//

import SwiftUI

struct AccessibilityPermissionSection: View {
    private let permission = PasteAccessPermission.shared

    var body: some View {
        Section {
            hero
                .padding(.vertical, 4)
        } header: {
            Text("Accessibility Permission")
        }
        .onAppear {
            permission.refresh()
        }
    }

    // MARK: - 子视图

    private var hero: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: permission.isAuthorized
                                ? [Color.green.opacity(0.72), Color.green]
                                : [Color.orange.opacity(0.72), Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: permission.isAuthorized
                    ? "checkmark.shield.fill"
                    : "hand.raised.slash.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            .shadow(
                color: (permission.isAuthorized ? Color.green : Color.orange).opacity(0.25),
                radius: 6,
                y: 2
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Paste Into Other Apps")
                    .font(.system(size: 15, weight: .semibold))
                Text("When you press Return or double-click an item, SixOne simulates ⌘V in the app you were using before opening the panel.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if permission.isAuthorized {
            badge(title: "Authorized", color: .green)
        } else {
            Button {
                permission.request()
            } label: {
                badge(title: "Grant Permission", color: .orange)
            }
            .buttonStyle(.plain)
        }
    }

    private func badge(title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}
