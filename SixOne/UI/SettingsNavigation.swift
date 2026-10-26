//
//  SettingsNavigation.swift
//  SixOne
//
//  设置面板的导航栈：侧栏点选与前进/后退共用历史，走过的面板截断而不追加。
//

import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case storage
    case privacy
    case shortcuts
    case about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .storage: "Storage"
        case .privacy: "Privacy"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .storage: "externaldrive"
        case .privacy: "hand.raised"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }
}

@Observable
final class SettingsNavigation {
    private(set) var path: [SettingsSection] = [.general]
    private(set) var forwardStack: [SettingsSection] = []

    /// 侧栏折叠状态；系统折叠按钮负责写入。
    var columnVisibility: NavigationSplitViewVisibility = .all
    /// 聚焦请求计数；每次显示窗口递增，视图据此聚焦侧栏。
    private(set) var sidebarFocusRequest = 0

    var current: SettingsSection { path.last ?? .general }
    var canGoBack: Bool { path.count > 1 }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func requestSidebarFocus() {
        sidebarFocusRequest += 1
    }

    /// 切到面板；已走过则截断，不追加。
    func go(to section: SettingsSection) {
        guard section != current else { return }
        forwardStack.removeAll()
        if let visited = path.firstIndex(of: section) {
            path = Array(path.prefix(through: visited))
        } else {
            path.append(section)
        }
    }

    func goBack() {
        guard canGoBack else { return }
        forwardStack.append(path.removeLast())
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        path.append(next)
    }

    /// 清空前进/后退栈并回到通用项。
    func reset() {
        forwardStack.removeAll()
        path = [.general]
        columnVisibility = .all
    }
}
