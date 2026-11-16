//
//  GeneralSettingsView.swift
//  SixOne
//
//  设置 → 通用：开机自启、语言入口与辅助功能授权。
//

import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    private let language = RuntimeLanguage.shared
    @State private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Section("General") {
            HStack {
                Text("Launch at Login")
                Spacer()
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .frame(height: 26)
            }
            .appTooltip(Localizer.string("Launch SixOne at login"))

            // 注册成功 ≠ 已生效：macOS 可能还在等用户批准。
            if launchAtLogin.needsApproval {
                HStack {
                    Text("macOS is waiting for you to allow SixOne to launch at login.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Login Items") {
                        launchAtLogin.openLoginItemsSettings()
                    }
                }
            } else if let failure = launchAtLogin.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Language")
                Spacer()
                Text(language.current.title)
                    .foregroundStyle(.secondary)
            }

            Text(Localizer.string(
                "SixOne follows the language set for it in macOS. Change it in System Settings → General → Language & Region → Applications, then reopen SixOne."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button(Localizer.string("Open Language & Region")) {
                openLanguageAndRegion()
            }
        }

        AccessibilityPermissionSection()
    }

    /// 系统设置 → 通用 → 语言与地区；按 App 语言在页面底部的「应用程序」列表。
    private func openLanguageAndRegion() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

private extension AppLanguage {
    var title: LocalizedStringKey {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "Chinese (Simplified)"
        }
    }
}
