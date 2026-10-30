//
//  PanelEditingSession.swift
//  SixOne
//
//  预览编辑会话：Esc 分层退出、取消编辑确认与查找栏命令。
//

import AppKit

final class PanelEditingSession {
    private let panel: ClipboardPanel
    private let previewState: PreviewState
    private let confirmationState: ConfirmationState
    private let moreActionsState: MoreActionsState
    private let hide: () -> Void

    init(
        panel: ClipboardPanel,
        previewState: PreviewState,
        confirmationState: ConfirmationState,
        moreActionsState: MoreActionsState,
        hide: @escaping () -> Void
    ) {
        self.panel = panel
        self.previewState = previewState
        self.confirmationState = confirmationState
        self.moreActionsState = moreActionsState
        self.hide = hide
    }

    var previewSurface: PreviewSurfaceProbe {
        PreviewSurfaceProbe(contentView: panel.contentView, firstResponder: panel.firstResponder)
    }

    /// Esc 分层退出：确认弹窗 → 查找栏 → 更多操作 → 预览 → 面板。
    func handleEscape() {
        if confirmationState.isPresenting {
            confirmationState.reset()
            return
        }
        if panel.attachedSheet != nil { return }
        if previewSurface.isFindBarVisible {
            closePreviewFindBar()
            return
        }
        if moreActionsState.isFocused {
            hide()
            return
        }
        if previewState.item != nil {
            if previewState.isEditing {
                requestCancelEditing()
            } else {
                previewState.close()
            }
            return
        }
        hide()
    }

    /// ⌘Q / ⌘W：编辑中先拦一道，处理完再退出。
    func handleQuitAttempt() -> Bool {
        guard previewState.isEditing else { return false }
        requestCancelEditing()
        return true
    }

    func requestCancelEditing() {
        guard previewState.isEditing else { return }
        guard previewState.hasUnsavedChanges else {
            previewState.cancelEditing()
            return
        }
        // 已有 sheet 压着（如 Finder 分享面板）就不再叠一层。
        guard panel.attachedSheet == nil else { return }
        confirmationState.isDiscardingPreviewEdit = true
        ConfirmationAlert.present(
            on: panel,
            title: Localizer.string("Discard Changes?"),
            message: Localizer.string("Your edits will be lost."),
            actionTitle: Localizer.string("Discard Changes"),
            onAction: { [weak self] in
                guard let self else { return }
                self.confirmationState.isDiscardingPreviewEdit = false
                self.previewState.cancelEditing()
            },
            onCancel: { [weak self] in
                guard let self else { return }
                self.confirmationState.isDiscardingPreviewEdit = false
                self.focusPreviewEditor()
            }
        )
    }

    /// 关查找栏并把焦点还给文本视图；再按 Esc 才退出预览。
    func closePreviewFindBar() {
        guard let textView = previewSurface.previewTextView() else { return }
        // 必须交给 NSTextFinder 关闭，直接翻 isFindBarVisible 会留下高亮浮层。
        TextPreviewView.dismissFindInterface(in: textView)
        textView.window?.makeFirstResponder(textView)
    }

    /// 用带 tag 的发送者让文本视图把命令转给内部 NSTextFinder；取不到视图时返回 false。
    @discardableResult
    func performPreviewFindCommand(_ command: NSTextFinder.Action) -> Bool {
        guard let textView = previewSurface.previewTextView() else { return false }
        let sender = NSMenuItem()
        sender.tag = command.rawValue
        textView.performTextFinderAction(sender)
        return true
    }

    private func focusPreviewEditor() {
        guard previewState.item != nil,
              let textView = previewSurface.previewTextView() else { return }
        panel.makeFirstResponder(textView)
    }
}
