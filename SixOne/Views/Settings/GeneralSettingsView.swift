//
//  GeneralSettingsView.swift
//  SixOne
//
//  设置 → 通用：开机自启、语言（重启后生效）与辅助功能授权。
//

import SwiftUI

struct GeneralSettingsView: View {
    let settings: SettingsStore

    @Environment(RuntimeLanguage.self) private var lang
    @State private var launchAtLogin = LaunchAtLogin()

    private var restartPending: Bool { settings.language != lang.current }

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

            Picker("Language", selection: languageBinding) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }

            if restartPending {
                HStack {
                    Text("The language change will take effect after restarting SixOne.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Now") {
                        AppRelauncher.relaunch()
                    }
                }
            }
        }

        AccessibilityPermissionSection()
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { settings.language },
            set: { settings.language = $0 }
        )
    }
}

private extension AppLanguage {
    var title: LocalizedStringKey {
        switch self {
        case .system: "Follow System"
        case .english: "English"
        case .simplifiedChinese: "Chinese (Simplified)"
        }
    }
}
