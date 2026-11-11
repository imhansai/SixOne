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
        linkOrigin: String?,
        isGroupFileView: Bool = false
    ) -> String {
        if isEditing { return Localizer.string("Edit") }
        switch item.kind {
        case .text, .color:
            return item.displayTitle
        case .image, .file:
            // 组内单文件先显示当前文件名，避免组别名盖掉正在看的文件。
            if isGroupFileView, let fileNameTitle { return fileNameTitle }
            return AliasNormalizer.displayable(item.alias) ?? fileNameTitle ?? item.displayTitle
        case .link:
            // 有 host 时用来源，否则用地址本身。
            return AliasNormalizer.displayable(item.alias) ?? linkOrigin ?? item.displayTitle
        }
    }
}
