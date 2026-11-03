//
//  PanelWindowLifecycle.swift
//  SixOne
//
//  面板窗口生命周期：显示/收起、定位、会话恢复与外部点击监听；
//  焦点判定、窗口事件与 Quick Look 播放分别交给协作者。
//

import AppKit
import QuickLookUI

final class PanelWindowLifecycle {
    private let panel: ClipboardPanel
    private let manager: ClipboardManager
    private let store: HistoryListStore
    private let panelState: PanelState
    private let confirmationState: ConfirmationState
    private let searchState: SearchState
    private let moreActionsState: MoreActionsState
    private let previewState: PreviewState
    private let navigationState: NavigationState
    private let noticeState: NoticeState
    private let shareState: ShareState
    private let quickPasteHintState: QuickPasteHintState
    private let cursor: PanelSelectionCursor
    private let sharing: PanelSharing

    private let focusGuard: PanelFocusGuard
    private let quickLook: PanelQuickLookPlayback
    private var eventMonitor: PanelWindowEventMonitor?

    var positionProvider: (() -> NSRect?)? {
        get { focusGuard.positionProvider }
        set { focusGuard.positionProvider = newValue }
    }
    /// 收起那一拍摘掉设置窗口的 key/main 候选，收完恢复（未建窗口时无需做事）。
    var setSettingsKeyAndMainSuspended: ((_ suspended: Bool) -> Void)?
    /// 面板显示/收起时回调。
    var onVisibilityChange: ((Bool) -> Void)?

    /// 上次收起时的界面快照；首次唤出前为 nil。
    private var session: PanelSession?
    private var previousApplication: NSRunningApplication?

    init(
        panel: ClipboardPanel,
        manager: ClipboardManager,
        store: HistoryListStore,
        panelState: PanelState,
        confirmationState: ConfirmationState,
        searchState: SearchState,
        moreActionsState: MoreActionsState,
        previewState: PreviewState,
        navigationState: NavigationState,
        noticeState: NoticeState,
        shareState: ShareState,
        quickPasteHintState: QuickPasteHintState,
        cursor: PanelSelectionCursor,
        sharing: PanelSharing
    ) {
        self.panel = panel
        self.manager = manager
        self.store = store
        self.panelState = panelState
        self.confirmationState = confirmationState
        self.searchState = searchState
        self.moreActionsState = moreActionsState
        self.previewState = previewState
        self.navigationState = navigationState
        self.noticeState = noticeState
        self.shareState = shareState
        self.quickPasteHintState = quickPasteHintState
        self.cursor = cursor
        self.sharing = sharing
        self.focusGuard = PanelFocusGuard(
            panel: panel,
            shareState: shareState,
            previewState: previewState,
            searchState: searchState
        )
        self.quickLook = PanelQuickLookPlayback(panel: panel)

        self.eventMonitor = PanelWindowEventMonitor(
            panel: panel,
            onResignKey: { [weak self] in
                // 不恢复原应用，避免 SixOne 自己的设置窗口抢 key 时切走应用。
                self?.quickPasteHintState.cancel()
                self?.hideIfFocusLeft(restoresPreviousApplication: false)
            },
            onBecomeKey: { [weak self] in
                self?.activateApp()
            },
            onBecomeActive: { [weak self] in
                guard let self, case .picking = self.shareState.stage else { return }
                self.sharing.finishPickingSessions()
            }
        )
    }

    isolated deinit {
        eventMonitor?.removeAll()
    }

    /// 唤起面板前的前台应用；粘贴流程据此找回目标。
    var previousApplicationForPaste: NSRunningApplication? { previousApplication }

    // MARK: - 显示 / 收起

    func toggle(anchor: PanelAnchor) {
        if panel.isVisible {
            hide()
        } else {
            show(anchor: anchor)
        }
    }

    func show(anchor: PanelAnchor) {
        guard !panel.isVisible else { return }
        previousApplication = NSWorkspace.shared.frontmostApplication
        // 此刻前台仍是原应用：先认领唤出前那次复制，归属不会被面板激活改掉。
        let hadUnpolledPasteboardChange = manager.hasUnpolledPasteboardChange
        manager.pollPasteboard(attributingTo: previousApplication.map(SourceApplication.init))
        positionPanel(anchor: anchor)
        present()
        noticeState.message = nil
        searchState.isFocused = false
        moreActionsState.isFocused = false
        confirmationState.reset()
        sharing.finishPickingSessions()
        shareState.stage = .idle
        store.setListVisible(true)
        restoreSession(hadUnpolledPasteboardChange: hadUnpolledPasteboardChange)
        panelState.isVisible = true
        installMonitors()
        onVisibilityChange?(true)
    }

    /// 返回是否已请求交还激活（交接由系统异步完成）。
    @discardableResult
    func hide(restoresPreviousApplication: Bool = true) -> Bool {
        guard panel.isVisible || panelState.isVisible else { return false }
        // 收起按自动保存处理，避免未提交编辑随退出丢失；显式取消不会走到这里。
        commitEditingBeforeHiding()
        quickPasteHintState.cancel()
        captureSession()
        panel.makeFirstResponder(nil)
        searchState.isFocused = false
        moreActionsState.isFocused = false
        // 影片挂在视图树上，不停掉会在收起后继续出声。
        quickLook.suspend()
        sharing.finishPickingSessions()
        shareState.stage = .idle
        orderOutPanel()
        panelState.isVisible = false
        store.setListVisible(false)
        removeMonitors()
        // 收起时把焦点还给唤出前的应用；用 WindowServer 状态，NSApp.isActive 会晚一拍。
        var handedOff = false
        if restoresPreviousApplication,
           isAppFrontmost,
           let previousApplication,
           previousApplication !== NSRunningApplication.current {
            NSApp.yieldActivation(to: previousApplication)
            handedOff = previousApplication.activate()
        }
        onVisibilityChange?(false)
        return handedOff
    }

    /// 先显示再成为 key/main；不当 main 的话激活前移的会是设置窗口。
    private func present() {
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeMain()
    }

    private func commitEditingBeforeHiding() {
        guard previewState.isEditing else { return }
        previewState.finishEditing()
    }

    /// orderOut 会把设置窗口顶成 key/main，这一拍先摘下它的候选资格。
    private func orderOutPanel() {
        setSettingsKeyAndMainSuspended?(true)
        defer { setSettingsKeyAndMainSuspended?(false) }
        panel.orderOut(nil)
    }

    // MARK: - 会话挂起 / 恢复

    private func captureSession() {
        let firstVisible = navigationState.fullyVisibleFirstIndex
        session = PanelSession(
            previewItemID: previewState.item?.id,
            selectedItemID: cursor.selectedItemID,
            topVisibleRowID: store.rows.indices.contains(firstVisible) ? store.rows[firstVisible].id : nil,
            topVisibleIndex: firstVisible,
            isSelectionActive: navigationState.isSelectionActive
        )
    }

    /// 接回上次的预览、选中与滚动锚点；收起期间来过新复制就停到新顶部，停得深才不重载。
    /// `hadUnpolledPasteboardChange` 是唤出前刚认领的那次变化：入库还在后台路上。
    private func restoreSession(hadUnpolledPasteboardChange: Bool) {
        let storeHasNewContent = store.takeNewContentWhileHidden()
        let hasNewContent = storeHasNewContent
            || hadUnpolledPasteboardChange
            || manager.hasUnpolledPasteboardChange
        if hasNewContent || !(session?.isDeepScroll ?? false) {
            store.loadLatest()
        }

        // 挂起期间条目可能已被裁剪，预览项取不到就关闭（授权随 close() 释放）。
        if let previewID = session?.previewItemID,
           previewState.item != nil,
           manager.fetchLightItem(id: previewID) == nil {
            previewState.close()
        }

        quickLook.restoreIfNeeded(hasPreview: previewState.item != nil)

        if let resolution = session?.resolve(againstRows: store.rows, hasNewContent: hasNewContent) {
            cursor.selectedItemID = resolution.selectedItemID
            navigationState.isSelectionActive = resolution.isSelectionActive
            switch resolution.scrollTarget {
            case .top:
                navigationState.requestScrollToTop()
            case .row(let rowID):
                navigationState.requestScroll(toRow: rowID)
            case nil:
                break
            }
        } else {
            cursor.selectedItemID = nil
            navigationState.isSelectionActive = false
        }

        if previewState.item != nil, let textView = previewSurface.previewTextView() {
            panel.makeFirstResponder(textView)
        } else {
            panel.makeFirstResponder(panel.contentView)
        }
    }

    // MARK: - 焦点判定

    /// 用 WindowServer 侧状态而非 `NSApp.isActive`，避免焦点切换瞬间读到旧值。
    private var isAppFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// 焦点真的离开时才隐藏；延后一拍，等新 key 窗口落定，避免辅助面板抢焦点时误收。
    private func hideIfFocusLeft(restoresPreviousApplication: Bool, clickedOutside: Bool = false) {
        focusGuard.hideIfFocusLeft(
            restoresPreviousApplication: restoresPreviousApplication,
            clickedOutside: clickedOutside
        ) { [weak self] restores in
            self?.hide(restoresPreviousApplication: restores)
        }
    }

    /// 用 `activate(from:)` 把前台应用当作交出激活的一方；状态栏路径上 `NSApp.activate()` 不被批准。
    private func activateApp() {
        guard !isAppFrontmost else { return }
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            NSApp.activate()
            return
        }
        NSRunningApplication.current.activate(from: frontmost, options: [])
    }

    // MARK: - 定位

    private func positionPanel(anchor: PanelAnchor) {
        let screens = NSScreen.screens.map { PanelPositioner.Screen($0) }
        panel.setFrameOrigin(PanelPositioner.origin(
            for: anchor,
            panelSize: panel.frame.size,
            statusItemRect: positionProvider?(),
            mouseLocation: NSEvent.mouseLocation,
            screens: screens,
            mainScreen: NSScreen.main.map { PanelPositioner.Screen($0) } ?? screens.first
        ))
    }

    // MARK: - 监听

    private func installMonitors() {
        eventMonitor?.startOutsideClickMonitor { [weak self] in
            self?.hideIfFocusLeft(restoresPreviousApplication: true, clickedOutside: true)
        }
    }

    private func removeMonitors() {
        eventMonitor?.stopOutsideClickMonitor()
    }

    private var previewSurface: PreviewSurfaceProbe {
        PreviewSurfaceProbe(contentView: panel.contentView, firstResponder: panel.firstResponder)
    }
}
