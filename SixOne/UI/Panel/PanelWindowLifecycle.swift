//
//  PanelWindowLifecycle.swift
//  SixOne
//
//  面板窗口生命周期：显示/收起、定位、会话恢复、焦点判定与外部点击监听。
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

    var positionProvider: (() -> NSRect?)?
    /// 收起那一拍摘掉设置窗口的 key/main 候选，收完恢复（未建窗口时无需做事）。
    var setSettingsKeyAndMainSuspended: ((_ suspended: Bool) -> Void)?

    /// 上次收起时的界面快照；首次唤出前为 nil。
    private var session: PanelSession?
    /// 挂起期间摘下的 Quick Look 预览项。
    private var suspendedQuickLookItemURL: URL?
    private var previousApplication: NSRunningApplication?
    private var mouseMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var becomeKeyObserver: NSObjectProtocol?
    private var becomeActiveObserver: NSObjectProtocol?

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

        // 失去 key 时延后判定收起：resign 到达时新 key 窗口可能还没挂上。
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // 不恢复原应用，避免 SixOne 自己的设置窗口抢 key 时切走应用。
                self?.quickPasteHintState.cancel()
                self?.hideIfFocusLeft(restoresPreviousApplication: false)
            }
        }

        // 拿到 key 就激活应用：nonactivating 面板光成为 key 不会回到前台，手势只派给激活应用。
        becomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.activateApp()
            }
        }

        // 应用回到前台：停在「选服务」的分享会话已结束；执行中的服务由自身回话。
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, case .picking = self.shareState.stage else { return }
                self.sharing.finishPickingSessions()
            }
        }
    }

    isolated deinit {
        for token in [resignObserver, becomeKeyObserver, becomeActiveObserver] {
            if let token {
                NotificationCenter.default.removeObserver(token)
            }
        }
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
        positionPanel(anchor: anchor)
        present()
        noticeState.message = nil
        searchState.isFocused = false
        moreActionsState.isFocused = false
        confirmationState.reset()
        sharing.finishPickingSessions()
        shareState.stage = .idle
        store.setListVisible(true)
        restoreSession()
        panelState.isVisible = true
        installMonitors()
    }

    func hide(restoresPreviousApplication: Bool = true) {
        guard panel.isVisible || panelState.isVisible else { return }
        // 收起按自动保存处理，避免未提交编辑随退出丢失；显式取消不会走到这里。
        commitEditingBeforeHiding()
        quickPasteHintState.cancel()
        captureSession()
        panel.makeFirstResponder(nil)
        searchState.isFocused = false
        moreActionsState.isFocused = false
        // 影片挂在视图树上，不停掉会在收起后继续出声。
        suspendQuickLookPlayback()
        sharing.finishPickingSessions()
        shareState.stage = .idle
        orderOutPanel()
        panelState.isVisible = false
        store.setListVisible(false)
        removeMonitors()
        // 仍激活（Esc/⌘W）时把焦点还给原应用；点面板外时其他应用已激活。
        if restoresPreviousApplication, NSApp.isActive, let previousApplication {
            NSApp.yieldActivation(to: previousApplication)
            previousApplication.activate()
        }
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
    private func restoreSession() {
        // 复制后立刻唤出时轮询还没认领，事件仍在流水线里；同样按「有新复制」处理。
        let storeHasNewContent = store.takeNewContentWhileHidden()
        let hasNewContent = storeHasNewContent || manager.hasUnpolledPasteboardChange
        if hasNewContent || !(session?.isDeepScroll ?? false) {
            store.loadLatest()
        }

        // 挂起期间条目可能已被裁剪，预览项取不到就关闭（授权随 close() 释放）。
        if let previewID = session?.previewItemID,
           previewState.item != nil,
           manager.fetchLightItem(id: previewID) == nil {
            previewState.close()
        }

        restoreQuickLookItemIfNeeded()

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

    /// 影片播放跑在 QuickLookUIService，只有摘掉 previewItem 才会停（约 2s 尾音）。
    private func suspendQuickLookPlayback() {
        guard let view = previewSurface.quickLookView(),
              let url = view.previewItem as? URL,
              FilePreviewKind.isMovie(url) else { return }
        suspendedQuickLookItemURL = url
        view.previewItem = nil
    }

    private func restoreQuickLookItemIfNeeded() {
        let suspended = suspendedQuickLookItemURL
        suspendedQuickLookItemURL = nil
        guard previewState.item != nil, let url = suspended else { return }
        previewSurface.quickLookView()?.previewItem = url as NSURL
    }

    // MARK: - 焦点判定

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

    /// 焦点真的离开时才隐藏；延后一拍，等新 key 窗口落定，避免辅助面板抢焦点时误收。
    private func hideIfFocusLeft(restoresPreviousApplication: Bool, clickedOutside: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            guard PanelFocusPolicy.shouldHide(self.focusSnapshot(clickedOutside: clickedOutside)) else { return }
            self.hide(restoresPreviousApplication: restoresPreviousApplication)
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
        removeMonitors()

        // 点面板外只是线索，真正是否收起交给 hideIfFocusLeft。
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            guard !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.hideIfFocusLeft(restoresPreviousApplication: true, clickedOutside: true)
        }
    }

    private func removeMonitors() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
    }

    private var previewSurface: PreviewSurfaceProbe {
        PreviewSurfaceProbe(contentView: panel.contentView, firstResponder: panel.firstResponder)
    }
}
