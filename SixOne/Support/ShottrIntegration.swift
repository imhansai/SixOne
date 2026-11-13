//
//  ShottrIntegration.swift
//  SixOne
//
//  Shottr 深链：复制图片后让它从剪贴板加载。
//

import AppKit

@MainActor
enum ShottrIntegration {
    private static let bundleIdentifier = "cc.ffitch.shottr"
    private static let clipboardDeepLink = URL(string: "shottr://load/clipboard")!

    static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    static func canOpen(_ item: ClipboardItem) -> Bool {
        item.kind == .image && item.imageData != nil
    }

    /// 打开深链；首次由 Shottr 弹窗确认。
    static func loadFromClipboard() -> Bool {
        NSWorkspace.shared.open(clipboardDeepLink)
    }
}
