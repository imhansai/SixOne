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
    let fileURL: URL
    let onHandOff: () -> Void

    @State private var defaultApp: URL?
    @State private var availableApps: [URL] = []

    var body: some View {
        Menu {
            if let defaultApp {
                Button(String(format: Localizer.string("Open in %@"), defaultApp.displayName)) {
                    openIn(defaultApp)
                }
                Divider()
                ForEach(availableApps.filter { $0 != defaultApp }, id: \.self) { app in
                    Button(app.displayName) {
                        openIn(app)
                    }
                }
                Divider()
            } else {
                ForEach(availableApps, id: \.self) { app in
                    Button(app.displayName) {
                        openIn(app)
                    }
                }
                if !availableApps.isEmpty {
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

    private func loadApps() {
        if defaultApp == nil {
            defaultApp = NSWorkspace.shared.urlForApplication(toOpen: fileURL)
        }
        if availableApps.isEmpty {
            availableApps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
        }
    }

    private func openIn(_ app: URL) {
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
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
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
