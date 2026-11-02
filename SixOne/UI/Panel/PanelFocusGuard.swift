//
//  PanelFocusGuard.swift
//  SixOne
//
//  焦点离开后的收起判定：采集现场、交给 `PanelFocusPolicy`，延后一拍再执行。
//

import AppKit

final class PanelFocusGuard {
    private let panel: ClipboardPanel
    private let shareState: ShareState
    private let previewState: PreviewState
    private let searchState: SearchState

    /// 状态栏图标位置；用于判断用户是否正按着状态项。
    var positionProvider: (() -> NSRect?)?

    init(
        panel: ClipboardPanel,
        shareState: ShareState,
        previewState: PreviewState,
        searchState: SearchState
    ) {
        self.panel = panel
        self.shareState = shareState
        self.previewState = previewState
        self.searchState = searchState
    }

    /// 焦点真的离开时才隐藏；延后一拍，等新 key 窗口落定，避免辅助面板抢焦点时误收。
    func hideIfFocusLeft(
        restoresPreviousApplication: Bool,
        clickedOutside: Bool = false,
        hide: @escaping (_ restoresPreviousApplication: Bool) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            guard PanelFocusPolicy.shouldHide(self.focusSnapshot(clickedOutside: clickedOutside)) else { return }
            hide(restoresPreviousApplication)
        }
    }

    // MARK: - 现场采集

    /// 用 WindowServer 侧状态而非 `NSApp.isActive`，避免焦点切换瞬间读到旧值。
    private var isAppFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// 前台是别的进程的非 regular 辅助面板（自动填充、指纹认证）；排除本进程。
    private var isSystemHelperFrontmost: Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        return frontmost.activationPolicy != .regular
    }

    /// 搜索框或预览正文是否正在编辑；面板失 key 后编辑会话仍在，所以仍可据此判断。
    private var isEditingText: Bool {
        previewState.isEditing || searchState.isFocused || panel.firstResponder is NSTextView
    }

    /// 用类型判断而非 `.shared`，避免比较时把字体/颜色面板提前创建出来。
    private var isTextAuxiliaryPanelKey: Bool {
        guard let keyWindow = NSApp.keyWindow else { return false }
        return keyWindow is NSFontPanel || keyWindow is NSColorPanel
    }

    /// 正按着菜单栏状态项；这一下由按钮动作（鼠标抬起）负责，不能收面板。
    private var isPressingStatusItem: Bool {
        guard NSEvent.pressedMouseButtons != 0 else { return false }
        guard let rect = positionProvider?() else { return false }
        return rect.contains(NSEvent.mouseLocation)
    }

    /// 查现场交给 `PanelFocusPolicy`；`clickedOutside` 表示用户主动点了面板外面。
    private func focusSnapshot(clickedOutside: Bool) -> PanelFocusSnapshot {
        PanelFocusSnapshot(
            isSharing: shareState.isActive,
            hasAttachedSheet: panel.attachedSheet != nil,
            isPressingStatusItem: isPressingStatusItem,
            isAppFrontmost: isAppFrontmost,
            isPanelKeyWindow: panel.isKeyWindow,
            isTextAuxiliaryPanelKey: isTextAuxiliaryPanelKey,
            hasApplicationSheet: NSApp.keyWindow?.sheetParent != nil,
            isEditingText: isEditingText,
            clickedOutside: clickedOutside,
            isSystemHelperFrontmost: isSystemHelperFrontmost,
            hasKeyWindow: NSApp.keyWindow != nil
        )
    }
}
