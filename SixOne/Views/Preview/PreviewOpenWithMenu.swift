//
//  PreviewOpenWithMenu.swift
//  SixOne
//
//  预览顶栏的打开方式菜单与链接打开按钮。
//

import AppKit
import SwiftUI

/// 仿 QuickLook 菜单；应用列表仅首次出现时查询，避免反复枚举 LaunchServices。
struct PreviewOpenWithMenu: View {
    let enumerationURL: URL
    let resolveOpenURL: () -> URL?
    let resolveRevealURL: () -> URL?
    let onOpenInShottr: (() -> Void)?
    let onHandOff: () -> Void

    @State private var defaultApp: URL?
    @State private var availableApps: [URL] = []

    var body: some View {
        let apps = menuApps
        return Menu {
            if let defaultApp {
                Button(String(format: Localizer.string("Open in %@"), defaultApp.displayName)) {
                    openIn(defaultApp)
                }
                Divider()
                ForEach(apps.filter { $0 != defaultApp }, id: \.self) { app in
                    Button(app.displayName) {
                        openIn(app)
                    }
                }
                Divider()
            } else {
                ForEach(apps, id: \.self) { app in
                    Button(app.displayName) {
                        openIn(app)
                    }
                }
                if !apps.isEmpty {
                    Divider()
                }
            }
            Button(Localizer.string("Reveal in Finder")) {
                revealInFinder()
            }
        } label: {
            PreviewHeaderMenuLabel(systemImage: "arrow.up.forward.app")
        }
        .buttonStyle(.plain)
        .appTooltip(Localizer.string("Open with"))
        .accessibilityLabel(Localizer.string("Open with"))
        .onAppear {
            loadApps()
        }
    }

    /// Shottr 未注册当前格式时，补进列表并改走剪贴板。
    private var shottrViaClipboard: URL? {
        guard onOpenInShottr != nil,
              let shottr = ShottrIntegration.applicationURL,
              !availableApps.contains(shottr) else { return nil }
        return shottr
    }

    private var menuApps: [URL] {
        guard let shottr = shottrViaClipboard else { return availableApps }
        return [shottr] + availableApps
    }

    private func loadApps() {
        if defaultApp == nil {
            defaultApp = NSWorkspace.shared.urlForApplication(toOpen: enumerationURL)
        }
        if availableApps.isEmpty {
            availableApps = NSWorkspace.shared.urlsForApplications(toOpen: enumerationURL)
        }
    }

    private func openIn(_ app: URL) {
        if app == shottrViaClipboard, let onOpenInShottr {
            onOpenInShottr()
            return
        }
        guard let fileURL = resolveOpenURL() else { return }
        if let defaultApp, app == defaultApp {
            NSWorkspace.shared.open(fileURL)
        } else {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([fileURL], withApplicationAt: app, configuration: config) { _, error in
                if error != nil {
                    NSWorkspace.shared.open(fileURL)
                }
            }
        }
        onHandOff()
    }

    private func revealInFinder() {
        guard let url = resolveRevealURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        onHandOff()
    }
}

struct PreviewLinkOpenButton: View {
    let url: URL
    let onHandOff: () -> Void
    let onError: (String) -> Void

    var body: some View {
        let isWeb = Self.isWebScheme(url.scheme)
        let titleKey: String.LocalizationValue = isWeb ? "Open in Browser" : "Open Link"
        PreviewHeaderActionButton(
            systemImage: isWeb ? "safari" : "arrow.up.forward.app",
            help: Localizer.string(titleKey)
        ) {
            guard NSWorkspace.shared.open(url) else {
                onError(String(
                    format: Localizer.string("Cannot open link: %@"),
                    url.absoluteString
                ))
                return
            }
            onHandOff()
        }
    }

    nonisolated static func isWebScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
