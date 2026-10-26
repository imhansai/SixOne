//
//  PanelPasteFlow.swift
//  SixOne
//  把条目粘进别的应用：校验 → 写回 → 收起面板 → 激活原应用 → 投递 ⌘V。

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import os

struct PanelPasteFlow {
    let manager: ClipboardManager
    let noticeState: NoticeState
    let requestReveal: (UUID) -> Void
    let previousApplication: () -> NSRunningApplication?
    let hide: () -> Void

    private let logger = AppLog.logger("PanelPaste")

    func paste(_ item: ClipboardItem, asPlainText: Bool = false, fileIndex: Int? = nil) {
        // 按 bookmark 解析路径：文件移入废纸篓后原路径仍在，不能只看文件系统。
        // 整组粘贴只要有任一文件还在就放行；指定 fileIndex 时只检查那一个。
        if item.kind == .file {
            let urls = manager.resolvedFileURLs(for: item)
            if let fileIndex {
                guard item.allFilePaths.indices.contains(fileIndex) else {
                    logger.warning("粘贴前检查：组内文件下标越界 \(fileIndex)")
                    return
                }
                guard urls.indices.contains(fileIndex), urls[fileIndex] != nil else {
                    let path = item.allFilePaths[fileIndex]
                    logger.warning("粘贴前检查：文件不存在，拒绝粘贴 \(path)")
                    noticeState.showMissingFile(URL(fileURLWithPath: path).lastPathComponent)
                    return
                }
            } else if !urls.contains(where: { $0 != nil }) {
                let path = item.allFilePaths.first ?? ""
                let label = item.fileCount > 1 ? item.displayTitle : URL(fileURLWithPath: path).lastPathComponent
                logger.warning("粘贴前检查：文件不存在，拒绝粘贴 \(path)")
                noticeState.showMissingFile(label)
                return
            }
        }

        // 未授权时提示并申请，本次不投递。
        guard PasteAccessPermission.shared.ensureGranted() else {
            noticeState.message = Localizer.string(
                "Accessibility permission required to paste into other apps. Grant it when prompted or in System Settings, then try Return or double-click again."
            )
            return
        }

        // 先探测事件再动剪贴板：投递发生在收起之后，失败提示已没人看得到。
        guard Self.canSynthesizePasteShortcut() else {
            logger.error("无法创建 ⌘V 键盘事件，已放弃本次粘贴（剪贴板未改动）")
            noticeState.message = Localizer.string(
                "Could not send ⌘V to the previous app. Nothing was changed — check the Accessibility permission and try again."
            )
            return
        }

        if let fileIndex {
            manager.copy(item, fileAt: fileIndex)
        } else if asPlainText {
            manager.copyAsPlainText(item)
        } else {
            manager.copy(item)
        }
        requestReveal(item.id)
        hide()

        // 隔一拍再激活并投递，避免收起与激活挤在同一拍互相打架。
        DispatchQueue.main.async {
            let target = previousApplication()
            if let target, NSApp.isActive {
                NSApp.yieldActivation(to: target)
            }
            target?.activate()
            waitUntilFrontmostThenPaste(target)
        }
    }

    /// 只探测不持有：`CGEvent` 不是 `Sendable`，不能跨队列传递。
    private static func canSynthesizePasteShortcut() -> Bool {
        CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) != nil
            && CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) != nil
    }

    /// 轮询前台进程号再投 ⌘V；目标已退出或超时就不投，绝不把内容粘进无关应用。
    private func waitUntilFrontmostThenPaste(
        _ target: NSRunningApplication?,
        deadline: Date? = nil
    ) {
        guard let target, !target.isTerminated else {
            abandonPaste("目标应用已退出")
            return
        }
        let deadline = deadline ?? Date().addingTimeInterval(Self.activationTimeout)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
            sendPasteShortcut()
            return
        }
        guard Date() < deadline else {
            abandonPaste("等待目标应用回到前台超时")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationPollInterval) { [self] in
            waitUntilFrontmostThenPaste(target, deadline: deadline)
        }
    }

    private func abandonPaste(_ reason: String) {
        logger.warning("\(reason)，已放弃投递 ⌘V（剪贴板保留本次内容）")
        NSSound.beep()
    }

    /// 最多等 0.4s；宁可这次不粘，也不投给当前碰巧在前台的应用。
    private static let activationTimeout: TimeInterval = 0.4
    private static let activationPollInterval: TimeInterval = 0.02

    private func sendPasteShortcut() {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            logger.error("投递 ⌘V 时事件创建失败")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
