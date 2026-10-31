//
//  PreviewHeaderModel.swift
//  SixOne
//
//  预览顶栏的标题与复制入口：纯值输入，不依赖视图状态。
//

import Foundation

/// 主标题后的复制按钮。
struct PreviewHeaderCopy {
    let text: String
    let help: String
}

enum PreviewHeaderCopyAction {
    @MainActor
    static func make(
        for item: ClipboardItem,
        isEditing: Bool,
        fileNameTitle: String?,
        linkOrigin: String?
    ) -> PreviewHeaderCopy? {
        guard !isEditing else { return nil }
        switch item.kind {
        case .text:
            guard let text = item.text, !text.isEmpty else { return nil }
            return PreviewHeaderCopy(text: text, help: Localizer.string("Copy Text"))
        case .image, .file:
            guard let fileNameTitle, !fileNameTitle.isEmpty else { return nil }
            return PreviewHeaderCopy(text: fileNameTitle, help: Localizer.string("Copy File Name"))
        case .link:
            if let linkOrigin {
                return PreviewHeaderCopy(text: linkOrigin, help: Localizer.string("Copy Origin"))
            }
            // 无 host 的链接，复制地址本身。
            guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return PreviewHeaderCopy(text: text, help: Localizer.string("Copy Link"))
        case .color:
            guard let hex = item.colorHexString else { return nil }
            return PreviewHeaderCopy(text: hex, help: Localizer.string("Copy Hex Value"))
        }
    }
}

/// 预览顶栏主标题：各类型都尽量给出内容身份，而不是类别名。
enum PreviewHeaderTitle {
    @MainActor
    static func mainTitle(
        for item: ClipboardItem,
        isEditing: Bool,
        fileNameTitle: String?,
        linkOrigin: String?
    ) -> String {
        if isEditing { return Localizer.string("Edit") }
        switch item.kind {
        case .text, .color:
            // 文本取首行、颜色取色值，比类别名更能辨认。
            return item.displayTitle
        case .image, .file:
            return fileNameTitle ?? item.displayTitle
        case .link:
            // 无 host 的链接（mailto: 等）用地址本身。
            return linkOrigin ?? item.displayTitle
        }
    }
}
