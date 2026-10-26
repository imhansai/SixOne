//
//  PrivacySettingsView.swift
//  SixOne
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 设置 → 隐私：维护「忽略的应用程序」列表；这些应用在前台复制时不写入历史。
struct PrivacySettingsView: View {
    let settings: SettingsStore
    @State private var selectedAppIDs: Set<IgnoredApplication.ID> = []

    var body: some View {
        Section {
            Table(settings.ignoredApps, selection: $selectedAppIDs) {
                TableColumn("Application") { app in
                    HStack(spacing: 8) {
                        Image(nsImage: ApplicationIconCache.icon(forPath: app.path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(app.displayName)
                            .lineLimit(1)
                    }
                }
                TableColumn("Bundle Identifier") { app in
                    Text(app.bundleIdentifier)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .frame(minHeight: 220)
            .overlay {
                if settings.ignoredApps.isEmpty {
                    Text("No applications are ignored yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 10) {
                Button {
                    addFromFinder()
                } label: {
                    Label("Add from Applications…", systemImage: "plus")
                }

                Button {
                    removeSelected()
                } label: {
                    Label("Remove Selected", systemImage: "minus")
                }
                .disabled(selectedAppIDs.isEmpty)

                Spacer()

                Button {
                    settings.restoreDefaultIgnoredApps()
                    selectedAppIDs.removeAll()
                } label: {
                    Label("Restore Default List", systemImage: "arrow.counterclockwise")
                }
            }
        } header: {
            Text("Ignored Applications")
        } footer: {
            Text("Copies made in these applications will not be recorded in clipboard history.")
        }
    }

    // MARK: - 添加 / 移除

    private func addFromFinder() {
        let panel = NSOpenPanel()
        panel.title = Localizer.string("Choose Applications to Ignore")
        panel.message = Localizer.string("Choose one or more applications. Their copies will not be recorded.")
        panel.prompt = Localizer.string("Add")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }

        var updated = settings.ignoredApps
        let existingBundleIDs = Set(settings.ignoredApps.map(\.bundleIdentifier))
        for url in panel.urls {
            guard let app = Self.ignoredApplication(at: url),
                  !existingBundleIDs.contains(app.bundleIdentifier) else { continue }
            updated.append(app)
        }
        if updated.count != settings.ignoredApps.count {
            settings.ignoredApps = updated
        }
    }

    private func removeSelected() {
        guard !selectedAppIDs.isEmpty else { return }
        settings.ignoredApps.removeAll { selectedAppIDs.contains($0.id) }
        selectedAppIDs.removeAll()
    }

    private static func ignoredApplication(at url: URL) -> IgnoredApplication? {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier else { return nil }
        let displayName = IgnoredApplication.localizedDisplayName(at: url)
            ?? url.deletingPathExtension().lastPathComponent
        return IgnoredApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            path: url.path
        )
    }
}

/// 应用图标缓存，避免 Table 每次重绘都做同步 I/O 与解码。
private enum ApplicationIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(forPath path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}
