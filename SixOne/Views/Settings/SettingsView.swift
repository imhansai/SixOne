//
//  SettingsView.swift
//  SixOne
//
//  设置窗口外壳：侧栏 + 详情区 + 前进/后退。
//

import SwiftUI

struct SettingsView: View {
    /// 侧栏宽度范围：min < max 才拖得动。
    private static let sidebarMinWidth: CGFloat = 180
    private static let sidebarMaxWidth: CGFloat = 200

    @FocusState private var isSidebarFocused: Bool

    @Bindable var navigation: SettingsNavigation
    let settings: SettingsStore
    let hotKeyManager: HotKeyManager
    let loadStorageStats: () async -> HistoryStorageStats
    let onClearHistory: () -> Void

    var body: some View {
        // 折叠交给自带的 sidebarToggle，收起后仍能把侧栏叫回来。
        NavigationSplitView(columnVisibility: $navigation.columnVisibility) {
            List(SettingsSection.allCases, selection: selectionBinding) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(
                min: Self.sidebarMinWidth,
                ideal: Self.sidebarMinWidth,
                max: Self.sidebarMaxWidth
            )
            .focused($isSidebarFocused)
            .simultaneousGesture(TapGesture().onEnded { focusSidebarOnClick() })
            .onAppear { focusSidebar() }
            .onChange(of: navigation.sidebarFocusRequest) { focusSidebar() }
        } detail: {
            SettingsDetailView(
                navigation: navigation,
                settings: settings,
                hotKeyManager: hotKeyManager,
                loadStorageStats: loadStorageStats,
                onClearHistory: onClearHistory
            )
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: navigation.goBack) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!navigation.canGoBack)
                    .keyboardShortcut("[", modifiers: [.command])
                    .appTooltip(Localizer.string("Back"))

                    Button(action: navigation.goForward) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!navigation.canGoForward)
                    .keyboardShortcut("]", modifiers: [.command])
                    .appTooltip(Localizer.string("Forward"))
                }
            }
        }
    }

    /// 侧栏选中：由导航栈决定截断还是追加。
    private var selectionBinding: Binding<SettingsSection?> {
        Binding(
            get: { navigation.current },
            set: { newValue in
                guard let newValue else { return }
                navigation.go(to: newValue)
                focusSidebarOnClick()
            }
        )
    }

    private func focusSidebarOnClick() {
        guard !isSidebarFocused else { return }
        focusSidebar()
    }

    /// 把焦点交给侧栏；首帧直接赋值会被详情区抢走，先清再下一拍置位。
    private func focusSidebar() {
        guard navigation.columnVisibility != .detailOnly else { return }
        isSidebarFocused = false
        DispatchQueue.main.async { isSidebarFocused = true }
    }
}

#if DEBUG
extension SettingsView {
    static var preview: SettingsView {
        SettingsView(
            navigation: SettingsNavigation(),
            settings: SettingsStore(),
            hotKeyManager: HotKeyManager(onTrigger: {}),
            loadStorageStats: { HistoryStorageStats(itemCount: nil, byteCount: nil) },
            onClearHistory: {}
        )
    }
}

// 预览要注入语言环境，否则通用页与快捷键录制器访问时会抛运行时错误。
#Preview {
    SettingsView.preview
        .environment(RuntimeLanguage.shared)
        .environment(\.locale, RuntimeLanguage.shared.locale)
}
#endif
