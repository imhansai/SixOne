//
//  AboutSettingsView.swift
//  SixOne
//
//  设置 → 关于：版本与源码地址。
//

import SwiftUI

struct AboutSettingsView: View {
    private static let repoURL = URL(string: "https://github.com/imhansai/SixOne")!
    private static let licenseURL = repoURL.appending(path: "blob/main/LICENSE")

    var body: some View {
        Section("About") {
            HStack(spacing: 10) {
                logo
                VStack(alignment: .leading, spacing: 2) {
                    Text("SixOne")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Version \(appVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }

        Section("Source") {
            linkRow("GitHub", destination: Self.repoURL)
        }

        Section("License") {
            linkRow("MIT License", destination: Self.licenseURL)
        }
    }

    private func linkRow(_ title: LocalizedStringKey, destination: URL) -> some View {
        Link(destination: destination) {
            Text(title)
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .appTooltip(destination.absoluteString)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var logo: some View {
        Image(systemName: "doc.on.clipboard")
            .font(.system(size: 32, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 56, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
            )
    }
}
