//
//  PanelState.swift
//  SixOne
//  面板界面状态容器：只装界面状态，不含业务规则。

import Foundation
import Observation

@Observable
final class PanelState {
    var isVisible = false
}

/// 面板上的模态二次确认：清空历史、删除单条、丢弃编辑。
@Observable
final class ConfirmationState {
    var isClearingHistory = false
    var pendingDeletionID: UUID?
    var isDiscardingPreviewEdit = false

    var isPresenting: Bool {
        isClearingHistory || pendingDeletionID != nil || isDiscardingPreviewEdit
    }

    func reset() {
        isClearingHistory = false
        pendingDeletionID = nil
        isDiscardingPreviewEdit = false
    }
}

@Observable
final class SearchState {
    var text = ""
    var isFocused = false
    var focusRequestID = 0
    var blurRequestID = 0

    func resignFocus() {
        guard isFocused else { return }
        isFocused = false
        blurRequestID += 1
    }
}

@Observable
final class MoreActionsState {
    var isFocused = false
    var focusRequestID = 0

    func resignFocus() {
        guard isFocused else { return }
        isFocused = false
    }
}

/// 复制反馈：SwiftUI 据此显示 checkmark 动画。
@Observable
final class CopyState {
    /// 值变即触发；同一条目重复复制不重复触发。
    var itemID: UUID?
    /// checkmark 动画期间的高亮条目；行视图直接观察它。
    var feedbackItemID: UUID?
}

@Observable
final class NoticeState {
    var message: String?
}

/// 文件失联/不可读的统一提示入口。
extension NoticeState {
    func showMissingFile(_ name: String) {
        message = String(format: Localizer.string("File no longer exists: %@"), name)
    }

    func showInaccessibleFile(_ name: String) {
        message = String(format: Localizer.string("Cannot access file: %@"), name)
    }

    /// 文件组只能从历史列表打开，预览间切换会换掉整套键盘语义。
    func showGroupPreviewRequiresList() {
        message = Localizer.string("Select the file group in the history list to preview it.")
    }
}

/// 分享进行期间面板不因失焦收起；外部分享界面抢焦点属于本次操作。
@Observable
final class ShareState {
    enum Stage {
        case idle
        /// 分享面板已打开、还没选服务。
        case picking
        /// 服务正在执行，只能等它自己回话。
        case running
    }

    var stage: Stage = .idle

    var isActive: Bool { stage != .idle }
}

/// 列表要滚到哪里。
enum HistoryListScrollTarget: Equatable {
    /// 滚到某一行；用 id 而非行号，因为列表随时会被置顶、裁剪或换掉。
    case row(UUID)
    /// 滚回顶部；换搜索词时列表整份替换，没有行 id 可用。
    case top
}

/// 列表的一次滚动命令；排队保证快速 ⌘↑/⌘↓ 的中间按键不丢。
struct HistoryListScrollCommand: Equatable {
    var target: HistoryListScrollTarget
    var isEndpointJump: Bool = false
    /// 发出命令时选中项已在目标端点，用于判断「按了但没动」。
    var isSelectionAlreadyAtEndpoint: Bool = false
}

/// 键盘导航状态：选中、待滚动行与列表发布的首个完整可见行。
@Observable
final class NavigationState {
    var selectedItemID: UUID?
    /// 已排队、待列表下一轮取走的滚动命令。
    @ObservationIgnored private var pendingScrollCommands: [HistoryListScrollCommand] = []
    /// 每次入队自增，让选中未变时也触发一轮更新。
    private(set) var scrollRevision = 0
    /// 复制 / 粘贴置顶后，等条目到第 0 行再滚进视野（用 id，置顶会换行号）。
    private(set) var pendingRevealItemID: UUID?
    /// 首个完整可见行；会话锚点与「是否滚到深处」都只认它。
    var fullyVisibleFirstIndex = 0
    /// 列表为键盘焦点时实心高亮；搜索框/更多操作聚焦时保留选中但置灰。
    var isSelectionActive = false

    /// 请求把某行滚进视野；端点跳转参数用于提示音判断。
    func requestScroll(
        toRow id: UUID,
        isEndpointJump: Bool = false,
        isSelectionAlreadyAtEndpoint: Bool = false
    ) {
        enqueueScrollCommand(
            HistoryListScrollCommand(
                target: .row(id),
                isEndpointJump: isEndpointJump,
                isSelectionAlreadyAtEndpoint: isSelectionAlreadyAtEndpoint
            )
        )
    }

    func requestScrollToTop(isEndpointJump: Bool = false) {
        enqueueScrollCommand(
            HistoryListScrollCommand(target: .top, isEndpointJump: isEndpointJump)
        )
    }

    func takePendingScrollCommands() -> [HistoryListScrollCommand] {
        defer { pendingScrollCommands.removeAll(keepingCapacity: true) }
        return pendingScrollCommands
    }

    func requestRevealAfterStoreChange(id: UUID) {
        pendingRevealItemID = id
    }

    func clearPendingReveal() {
        pendingRevealItemID = nil
    }

    private func enqueueScrollCommand(_ command: HistoryListScrollCommand) {
        pendingScrollCommands.append(command)
        scrollRevision &+= 1
    }
}

enum PanelAnchor {
    case statusItem
    case mouse
}
