//
//  PanelPasteFlow.swift
//  SixOne
//  把条目粘进别的应用：校验 → 写回 → 收起 → 激活原应用 → 投递 ⌘V。
//

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import os

// MARK: - 系统依赖端口

/// 投递 ⌘V 的键盘事件；生产实现用 CGEvent，测试可只记录调用。
@MainActor
protocol PasteEventPosting {
    /// 能否创建 ⌘V 事件；只探测，不发送。
    func canPostPasteShortcut() -> Bool
    func postPasteShortcut()
}

/// 应用激活与前台判定。
@MainActor
protocol PasteApplicationControlling {
    var isAppActive: Bool { get }
    var frontmostProcessIdentifier: pid_t? { get }
    func yieldActivation(to application: NSRunningApplication)
    func activate(_ application: NSRunningApplication)
    func isTerminated(_ application: NSRunningApplication) -> Bool
}

@MainActor
protocol PastePermissionChecking {
    func ensureGranted() -> Bool
}

/// 延后执行；测试用可手动驱动的队列。
@MainActor
protocol PasteScheduling {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void)
}

@MainActor
protocol PasteClock {
    var now: Date { get }
}

@MainActor
protocol PasteFeedback {
    func beep()
}

struct SystemPasteEventPoster: PasteEventPosting {
    private static let logger = AppLog.logger("PanelPaste")

    func canPostPasteShortcut() -> Bool {
        CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) != nil
            && CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) != nil
    }

    func postPasteShortcut() {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            Self.logger.error("投递 ⌘V 时事件创建失败")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

struct SystemPasteApplicationController: PasteApplicationControlling {
    var isAppActive: Bool { NSApp.isActive }
    var frontmostProcessIdentifier: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func yieldActivation(to application: NSRunningApplication) {
        NSApp.yieldActivation(to: application)
    }

    func activate(_ application: NSRunningApplication) {
        application.activate()
    }

    func isTerminated(_ application: NSRunningApplication) -> Bool {
        application.isTerminated
    }
}

struct SystemPastePermissionChecker: PastePermissionChecking {
    func ensureGranted() -> Bool {
        PasteAccessPermission.shared.ensureGranted()
    }
}

struct MainQueuePasteScheduler: PasteScheduling {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { action() }
        }
    }
}

struct SystemPasteClock: PasteClock {
    var now: Date { Date() }
}

struct SystemPasteFeedback: PasteFeedback {
    func beep() {
        NSSound.beep()
    }
}

/// 粘贴链路的系统依赖集合；测试替换其中任意一项。
struct PanelPasteEnvironment {
    var eventPoster: PasteEventPosting = SystemPasteEventPoster()
    var applicationController: PasteApplicationControlling = SystemPasteApplicationController()
    var permissionChecker: PastePermissionChecking = SystemPastePermissionChecker()
    var scheduler: PasteScheduling = MainQueuePasteScheduler()
    var clock: PasteClock = SystemPasteClock()
    var feedback: PasteFeedback = SystemPasteFeedback()
}

// MARK: - 粘贴流程

struct PanelPasteFlow {
    let manager: ClipboardManager
    let noticeState: NoticeState
    let requestReveal: (UUID) -> Void
    let previousApplication: () -> NSRunningApplication?
    let hide: () -> Void
    private let environment: PanelPasteEnvironment

    private let logger = AppLog.logger("PanelPaste")

    init(
        manager: ClipboardManager,
        noticeState: NoticeState,
        requestReveal: @escaping (UUID) -> Void,
        previousApplication: @escaping () -> NSRunningApplication?,
        hide: @escaping () -> Void,
        environment: PanelPasteEnvironment = PanelPasteEnvironment()
    ) {
        self.manager = manager
        self.noticeState = noticeState
        self.requestReveal = requestReveal
        self.previousApplication = previousApplication
        self.hide = hide
        self.environment = environment
    }

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
        guard environment.permissionChecker.ensureGranted() else {
            noticeState.message = Localizer.string(
                "Accessibility permission required to paste into other apps. Grant it when prompted or in System Settings, then try Return or double-click again."
            )
            return
        }

        // 先探测事件再动剪贴板：投递发生在收起之后，失败提示已没人看得到。
        guard environment.eventPoster.canPostPasteShortcut() else {
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
        environment.scheduler.schedule(after: 0) { [self] in
            let target = previousApplication()
            if let target, environment.applicationController.isAppActive {
                environment.applicationController.yieldActivation(to: target)
            }
            if let target {
                environment.applicationController.activate(target)
            }
            waitUntilFrontmostThenPaste(target)
        }
    }

    /// 轮询前台进程号再投 ⌘V；目标已退出或超时就不投，绝不把内容粘进无关应用。
    private func waitUntilFrontmostThenPaste(
        _ target: NSRunningApplication?,
        deadline: Date? = nil
    ) {
        guard let target, !environment.applicationController.isTerminated(target) else {
            abandonPaste("目标应用已退出")
            return
        }
        let deadline = deadline ?? environment.clock.now.addingTimeInterval(Self.activationTimeout)
        if environment.applicationController.frontmostProcessIdentifier == target.processIdentifier {
            environment.eventPoster.postPasteShortcut()
            return
        }
        guard environment.clock.now < deadline else {
            abandonPaste("等待目标应用回到前台超时")
            return
        }
        environment.scheduler.schedule(after: Self.activationPollInterval) { [self] in
            waitUntilFrontmostThenPaste(target, deadline: deadline)
        }
    }

    private func abandonPaste(_ reason: String) {
        logger.warning("\(reason)，已放弃投递 ⌘V（剪贴板保留本次内容）")
        environment.feedback.beep()
    }

    /// 最多等 0.4s；宁可这次不粘，也不投给当前碰巧在前台的应用。
    private static let activationTimeout: TimeInterval = 0.4
    private static let activationPollInterval: TimeInterval = 0.02
}
