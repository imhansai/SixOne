//
//  ClipboardPanelController.swift
//  SixOne
//  面板控制器：显示/隐藏/定位、会话恢复、面板级动作与键盘执行。

import AppKit
import QuickLookUI
import SwiftUI

/// 剪贴板面板控制：显示隐藏、焦点处理、菜单命令与键盘 action。
final class ClipboardPanelController: NSObject, NSWindowDelegate, PanelActionHandler, PanelKeyHandling, NSMenuItemValidation {
    private let panel: ClipboardPanel
    private let context: PanelContext
    /// 状态对象由 `PanelContext` 持有；这里直接引用，避免每次取值。
    private let manager: ClipboardManager
    private let store: HistoryListStore
    private let panelState: PanelState
    private let confirmationState: ConfirmationState
    private let searchState: SearchState
    private let moreActionsState: MoreActionsState
    private let previewState: PreviewState
    private let navigationState: NavigationState
    private let copyState: CopyState
    private let noticeState: NoticeState
    private let shareState: ShareState
    private let quickPasteHintState: QuickPasteHintState
    private let searchSession: PanelSearchSession
    /// 上次收起时的界面快照；首次唤出前为 nil。
    private var session: PanelSession?
    /// 挂起期间摘下的 Quick Look 预览项。
    private var suspendedQuickLookItemURL: URL?
    private var previousApplication: NSRunningApplication?

    var positionProvider: (() -> NSRect?)?

    var onOpenSettings: (() -> Void)?

    /// 收起那一拍摘掉设置窗口的 key/main 候选，收完恢复（未建窗口时无需做事）。
    var setSettingsKeyAndMainSuspended: ((_ suspended: Bool) -> Void)?

    private var mouseMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var becomeKeyObserver: NSObjectProtocol?
    private var becomeActiveObserver: NSObjectProtocol?
    private var hostingController: NSViewController?
    private lazy var previewLauncher = PreviewLauncher(
        manager: manager,
        previewState: previewState,
        noticeState: noticeState
    )
    private lazy var sharing = PanelSharing(
        manager: manager,
        shareState: shareState,
        noticeState: noticeState
    )
    /// 粘贴进别的应用：校验 → 写回 → 收起 → 投递 ⌘V。
    private lazy var pasteFlow = PanelPasteFlow(
        manager: manager,
        noticeState: noticeState,
        requestReveal: { [weak self] id in
            self?.navigationState.requestRevealAfterStoreChange(id: id)
        },
        previousApplication: { [weak self] in self?.previousApplication },
        hide: { [weak self] in self?.hide() }
    )
    private lazy var cursor = PanelSelectionCursor(
        store: store,
        navigationState: navigationState,
        previewState: previewState,
        previewLauncher: previewLauncher
    )
    private lazy var keyContext = PanelKeyContextProvider(
        panel: panel,
        searchState: searchState,
        moreActionsState: moreActionsState,
        confirmationState: confirmationState,
        previewState: previewState,
        selectedItemID: { [weak self] in self?.cursor.selectedItemID },
        visibleRowCount: { [weak self] in
            guard let range = self?.navigationState.fullyVisibleRange else { return 0 }
            return min(range.count, QuickPaste.rowLimit)
        }
    )
    private lazy var menuCommands = MenuKeyEquivalentIndex(menu: NSApp.mainMenu)
    private lazy var focusZones = PanelFocusZones(
        panel: panel,
        searchState: searchState,
        moreActionsState: moreActionsState,
        navigationState: navigationState,
        cursor: cursor,
        isFullKeyboardAccessEnabled: { NSApplication.shared.isFullKeyboardAccessEnabled }
    )

    init(context: PanelContext) {
        self.context = context
        self.manager = context.manager
        self.store = context.store
        self.panelState = context.panelState
        self.confirmationState = context.confirmationState
        self.searchState = context.searchState
        self.moreActionsState = context.moreActionsState
        self.previewState = context.previewState
        self.navigationState = context.navigationState
        self.copyState = context.copyState
        self.noticeState = context.noticeState
        self.shareState = context.shareState
        self.quickPasteHintState = context.quickPasteHintState
        self.searchSession = context.searchSession
        self.panel = PanelWindowFactory.makePanel()

        super.init()

        context.actions = self
        panel.delegate = self
        panel.keyHandler = self

        manager.onPersistenceFailure = { [weak self] reason in
            self?.noticeState.message = String(
                format: Localizer.string("Could not save clipboard history (%@). Your clipboard still works, but this change may not be kept."),
                reason
            )
        }

        self.hostingController = PanelWindowFactory.install(
            rootView: AnyView(makeRootView()),
            into: panel
        )

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

    private func makeRootView() -> some View {
        ClipboardListView(context: context)
            .environment(context)
            .environment(\.locale, RuntimeLanguage.shared.locale)
            .environment(RuntimeLanguage.shared)
    }

    // MARK: - 面板级动作（PanelActionHandler）

    func panelDidActivate(id: UUID, asPlainText: Bool) {
        guard let item = fullItem(id: id) else { return }
        // 无纯文本形态的条目回落普通粘贴。
        pasteFlow.paste(item, asPlainText: asPlainText && item.kind.hasPlainText)
    }

    func panelDidRequestDelete(id: UUID) {
        guard manager.fetchLightItem(id: id) != nil else { return }
        confirmationState.pendingDeletionID = id
        ConfirmationAlert.present(
            on: panel,
            title: Localizer.string("Delete Item?"),
            message: Localizer.string("This cannot be undone."),
            actionTitle: Localizer.string("Delete"),
            onAction: { [weak self] in self?.panelDidConfirmDelete(id: id) },
            onCancel: { [weak self] in self?.confirmationState.pendingDeletionID = nil }
        )
    }

    private func panelDidConfirmDelete(id: UUID) {
        confirmationState.pendingDeletionID = nil
        guard let item = manager.fetchLightItem(id: id) else { return }
        if previewState.item?.id == item.id {
            previewState.close()
        }
        manager.delete(id: item.id)
        if cursor.selectedItemID == item.id {
            cursor.selectedItemID = nil
            navigationState.isSelectionActive = false
        }
    }

    func panelDidPasteAsPlainText(id: UUID) {
        guard let item = fullItem(id: id) else { return }
        pasteFlow.paste(item, asPlainText: true)
    }

    func panelDidRequestOpen(id: UUID) {
        guard let item = fullItem(id: id) else { return }
        openExternally(item)
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

    var canRequestSettings: Bool { onOpenSettings != nil }

    func panelDidRequestSettings() {
        onOpenSettings?()
    }

    func panelDidHandOffToExternalApp() {
        hide(restoresPreviousApplication: false)
    }

    func panelDidRequestShare(id: UUID, anchorView: NSView) {
        sharing.shareRowItem(id: id, anchorView: anchorView)
    }

    func panelDidRequestFocusContent() {
        previewState.releaseGroupFilterFocus()
        panel.makeFirstResponder(panel.contentView)
    }

    func panelDidRequestGroupFileShare(at index: Int, anchorView: NSView) {
        guard let item = previewState.item, item.kind == .file, item.fileCount > 1 else { return }
        sharing.sharePreviewedFile(at: index, of: item, anchorView: anchorView)
    }

    func panelDidRequestShareGroup(anchorView: NSView?) {
        guard let item = previewState.item, item.kind == .file, item.fileCount > 1,
              let anchor = anchorView ?? panel.contentView else { return }
        sharing.sharePreviewedGroup(item, anchorView: anchor)
    }

    func panelDidInvokeGroupFileCommand(_ command: GroupFileCommand, index: Int) {
        handleGroupFileCommand(command, index: index)
    }

    func panelDidRequestEscape() {
        handleEscape()
    }

    func panelDidRequestCancelEditing() {
        requestCancelEditing()
    }

    func panelDidRequestCopyItem() {
        copySelectedItem()
    }

    func panelDidRequestPasteItem() {
        pasteSelectedItem()
    }

    func panelDidRequestSearchCancel() {
        if searchState.text.isEmpty {
            searchState.resignFocus()
        } else {
            searchSession.clear()
        }
    }

    func panelDidRequestSearchMoveDown() {
        guard !store.rows.isEmpty else { return }
        // 防抖尚未落库时先立即应用当前词，避免导航到旧结果。
        store.setSearchQuery(searchState.text)
        focusZones.focusList()
    }

    func panelDidRequestSearchTab(backwards: Bool) {
        focusZones.cycle(backwards: backwards)
    }

    private func fullItem(id: UUID) -> ClipboardItem? {
        manager.fetchFullItem(id: id)
    }

    func toggle(anchor: PanelAnchor) {
        if panel.isVisible {
            hide()
        } else {
            show(anchor: anchor)
        }
    }

    /// 先显示再成为 key/main；不当 main 的话激活前移的会是设置窗口。
    private func present() {
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeMain()
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

    func handleCloseWindow() {
        if previewState.isEditing {
            requestCancelEditing()
        } else {
            hide()
        }
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

    private func commitEditingBeforeHiding() {
        guard previewState.isEditing else { return }
        previewState.finishEditing()
    }

    func handleQuitAttempt() -> Bool {
        guard previewState.isEditing else { return false }
        requestCancelEditing()
        return true
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

    private func handleGroupFileCommand(_ command: GroupFileCommand, index: Int) {
        guard let item = previewState.item, item.kind == .file, item.fileCount > 1 else { return }
        switch command {
        case .paste:
            pasteFlow.paste(item, fileIndex: index)
        case .copy:
            copyGroupFile(at: index, of: item)
        case .open, .reveal:
            break
        }
    }

    private func copyGroupFile(at index: Int, of item: ClipboardItem) {
        if manager.copy(item, fileAt: index) {
            copyState.itemID = item.id
            return
        }
        let path = item.allFilePaths.indices.contains(index) ? item.allFilePaths[index] : ""
        noticeState.showMissingFile(URL(fileURLWithPath: path).lastPathComponent)
    }

    private func openExternally(_ item: ClipboardItem) {
        // 文件组逐个用各自默认应用打开；NSWorkspace 没有批量按默认应用打开的 API。
        if item.kind == .file, item.fileCount > 1 {
            let urls = manager.resolvedFileURLs(for: item).compactMap { $0 }
            guard !urls.isEmpty else {
                noticeState.showMissingFile(item.displayTitle)
                return
            }
            for url in urls { NSWorkspace.shared.open(url) }
            hide(restoresPreviousApplication: false)
            return
        }

        guard let url = manager.fileURL(for: item) else {
            // 文件条目是不存在了，图片条目是取不到内容。
            if item.kind == .file {
                noticeState.showMissingFile(item.displayTitle)
            } else {
                noticeState.showInaccessibleFile(item.displayTitle)
            }
            return
        }
        NSWorkspace.shared.open(url)
        hide(restoresPreviousApplication: false)
    }

    private func activateSelected(asPlainText: Bool) {
        guard let id = cursor.selectedItemID, let item = fullItem(id: id) else { return }
        pasteFlow.paste(item, asPlainText: asPlainText && item.kind.hasPlainText)
    }

    // MARK: - 菜单命令

    /// 命令作用条目：预览打开时优先预览项，否则按列表选中查库。
    private var currentLightItem: ClipboardItem? {
        if let preview = previewState.item { return preview }
        guard let id = cursor.selectedItemID else { return nil }
        return manager.fetchLightItem(id: id)
    }

    private var commandAvailability: PanelCommandAvailability {
        let item = currentLightItem
        let kind = item?.kind
        let hasOpenTarget = item.map { manager.canOpenExternally(id: $0.id) } ?? false
        let hasRevealableFile: Bool = {
            guard let item else { return false }
            if item.kind == .file, item.fileCount > 1 {
                return manager.resolvedFileURLs(for: item).contains { $0 != nil }
            }
            return manager.fileURL(for: item, allowTemporaryCopy: false) != nil
        }()
        let focusedGroupFileIndex: Int? = {
            guard let item, item.kind == .file, item.fileCount > 1 else { return nil }
            return previewState.focusedGroupFileIndex
        }()
        return PanelCommandAvailability(
            isPanelKeyWindow: panel.isKeyWindow,
            isTextEditing: isTextEditing,
            hasSelection: item != nil,
            selectionKind: kind,
            isPreviewing: previewState.item != nil,
            focusedGroupFileIndex: focusedGroupFileIndex,
            canOpenExternally: hasOpenTarget,
            hasRevealableFile: hasRevealableFile,
            hasHistory: !store.rows.isEmpty,
            isEditing: previewState.isEditing
        )
    }

    @objc func copy(_ sender: Any?) {
        copySelectedItem()
    }

    @objc func paste(_ sender: Any?) {
        pasteSelectedItem()
    }

    @objc func copyAsPlainText(_ sender: Any?) {
        guard let item = currentLightItem, item.kind.hasPlainText else { return }
        manager.copyAsPlainText(id: item.id)
        copyState.itemID = item.id
    }

    @objc func pasteAsPlainText(_ sender: Any?) {
        guard let item = currentLightItem, item.kind.hasPlainText,
              let full = fullItem(id: item.id) else { return }
        pasteFlow.paste(full, asPlainText: true)
    }

    @objc func delete(_ sender: Any?) {
        deleteSelectedItem()
    }

    @objc func previewSelectedItem(_ sender: Any?) {
        if previewState.item != nil {
            previewState.close()
            return
        }
        guard let item = currentLightItem, let full = fullItem(id: item.id) else { return }
        previewLauncher.present(full)
    }

    /// ⌘S：保存当前正文，但保持编辑态；「完成」才退出编辑。
    @objc func saveEditing(_ sender: Any?) {
        previewState.requestSave()
    }

    @objc func openSelectedItem(_ sender: Any?) {
        guard let item = currentLightItem, let full = fullItem(id: item.id) else { return }
        openExternally(full)
    }

    @objc func revealSelectedItem(_ sender: Any?) {
        guard let item = currentLightItem else { return }
        if item.kind == .file, item.fileCount > 1 {
            let urls = manager.resolvedFileURLs(for: item).compactMap { $0 }
            guard !urls.isEmpty else {
                noticeState.showMissingFile(item.displayTitle)
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        } else if let url = manager.fileURL(for: item, allowTemporaryCopy: false) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            noticeState.showMissingFile(item.displayTitle)
            return
        }
        hide(restoresPreviousApplication: false)
    }

    @objc func shareSelectedItem(_ sender: Any?) {
        guard let item = currentLightItem, let anchor = panel.contentView else { return }
        if previewState.item?.id == item.id, item.kind == .file, item.fileCount > 1 {
            if let index = previewState.focusedGroupFileIndex {
                sharing.sharePreviewedFile(at: index, of: item, anchorView: anchor)
            } else {
                sharing.sharePreviewedGroup(item, anchorView: anchor)
            }
            return
        }
        sharing.shareRowItem(id: item.id, anchorView: anchor)
    }

    @objc func clearHistory(_ sender: Any?) {
        panelDidRequestClearHistory()
    }

    func panelDidRequestClearHistory() {
        guard !store.rows.isEmpty else { return }
        confirmationState.isClearingHistory = true
        ConfirmationAlert.present(
            on: panel,
            title: Localizer.string("Clear History?"),
            message: Localizer.string("This deletes all clipboard history. It cannot be undone."),
            actionTitle: Localizer.string("Clear History"),
            onAction: { [weak self] in
                self?.manager.clearAll()
                self?.confirmationState.isClearingHistory = false
            },
            onCancel: { [weak self] in self?.confirmationState.isClearingHistory = false }
        )
    }

    @objc func focusSearch(_ sender: Any?) {
        focusZones.focusSearch()
    }

    /// 查找栏的 field editor 不实现 `performTextFinderAction:`，命令会落到这里转交文本视图。
    @objc func performTextFinderAction(_ sender: Any?) {
        guard let sender = sender as? NSMenuItem else { return }
        // 文件组列表的 Find… 该聚焦组内筛选框，而不是被内容盖住的外层搜索。
        if sender.tag == NSTextFinder.Action.showFindInterface.rawValue,
           let item = previewState.item,
           item.kind == .file, item.fileCount > 1,
           previewState.groupFileIndex == nil {
            searchState.resignFocus()
            previewState.focusGroupFilter()
            return
        }
        if let textView = previewSurface.previewTextView() {
            textView.performTextFinderAction(sender)
            return
        }
        if sender.tag == NSTextFinder.Action.showFindInterface.rawValue {
            focusZones.focusSearch()
        }
    }

    private func copySelectedItem() {
        guard let item = currentLightItem else { return }
        if item.kind == .file, item.fileCount > 1,
           let index = previewState.focusedGroupFileIndex {
            copyGroupFile(at: index, of: item)
            return
        }
        manager.copy(id: item.id)
        copyState.itemID = item.id
    }

    private func pasteSelectedItem() {
        guard let item = currentLightItem else { return }
        if item.kind == .file, item.fileCount > 1,
           let index = previewState.focusedGroupFileIndex {
            pasteFlow.paste(item, fileIndex: index)
            return
        }
        guard let full = fullItem(id: item.id) else { return }
        pasteFlow.paste(full)
    }

    /// ⌘+数字：先选中当前完整可见区的第 offset 行再粘贴；失败时面板保留并沿用现有提示。
    private func pasteVisibleRow(offset: Int, asPlainText: Bool) {
        guard let range = navigationState.fullyVisibleRange else { return }
        let index = range.lowerBound + offset
        guard range.contains(index), store.rows.indices.contains(index) else { return }
        let id = store.rows[index].id
        guard let full = fullItem(id: id) else { return }
        if asPlainText, !full.kind.hasPlainText { return }
        navigationState.selectedItemID = id
        pasteFlow.paste(full, asPlainText: asPlainText)
    }

    private func deleteSelectedItem() {
        guard let item = currentLightItem else { return }
        panelDidRequestDelete(id: item.id)
    }

    // MARK: - 菜单校验

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let availability = commandAvailability
        switch menuItem.action {
        case #selector(ClipboardPanelController.copy(_:)):
            return availability.isEnabled(.copy)
        case #selector(ClipboardPanelController.paste(_:)):
            return availability.isEnabled(.paste)
        case #selector(ClipboardPanelController.copyAsPlainText(_:)):
            return availability.isEnabled(.copyAsPlainText)
        case #selector(ClipboardPanelController.pasteAsPlainText(_:)):
            return availability.isEnabled(.pasteAsPlainText)
        case #selector(ClipboardPanelController.delete(_:)):
            return availability.isEnabled(.delete)
        case #selector(ClipboardPanelController.previewSelectedItem(_:)):
            menuItem.title = availability.isPreviewing
                ? Localizer.string("Close Preview")
                : Localizer.string("Preview")
            return availability.isEnabled(.preview)
        case #selector(ClipboardPanelController.saveEditing(_:)):
            return availability.isEnabled(.saveEditing)
        case #selector(ClipboardPanelController.openSelectedItem(_:)):
            return availability.isEnabled(.open)
        case #selector(ClipboardPanelController.revealSelectedItem(_:)):
            return availability.isEnabled(.reveal)
        case #selector(ClipboardPanelController.shareSelectedItem(_:)):
            return availability.isEnabled(.share)
        case #selector(ClipboardPanelController.clearHistory(_:)):
            return availability.isEnabled(.clearHistory)
        case #selector(ClipboardPanelController.focusSearch(_:)):
            return availability.isEnabled(.focusSearch)
        case #selector(ClipboardPanelController.performTextFinderAction(_:)):
            if menuItem.tag == NSTextFinder.Action.showFindInterface.rawValue {
                return panel.isKeyWindow
            }
            return previewSurface.previewTextView() != nil
        default:
            return false
        }
    }

    private var previewSurface: PreviewSurfaceProbe {
        PreviewSurfaceProbe(contentView: panel.contentView, firstResponder: panel.firstResponder)
    }

    /// 关查找栏并把焦点还给文本视图；再按 Esc 才退出预览。
    private func closePreviewFindBar() {
        guard let textView = previewSurface.previewTextView() else { return }
        // 必须交给 NSTextFinder 关闭，直接翻 isFindBarVisible 会留下高亮浮层。
        TextPreviewView.dismissFindInterface(in: textView)
        textView.window?.makeFirstResponder(textView)
    }

    /// 用带 tag 的发送者让文本视图把命令转给内部 NSTextFinder；取不到视图时返回 false。
    @discardableResult
    private func performPreviewFindCommand(_ command: NSTextFinder.Action) -> Bool {
        guard let textView = previewSurface.previewTextView() else { return false }
        let sender = NSMenuItem()
        sender.tag = command.rawValue
        textView.performTextFinderAction(sender)
        return true
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

    private func requestCancelEditing() {
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

    private func focusPreviewEditor() {
        guard previewState.item != nil,
              let textView = previewSurface.previewTextView() else { return }
        panel.makeFirstResponder(textView)
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

    // MARK: - 键盘：窗口 pre-dispatch + 标准 action

    /// 只处理 PanelKeyRouter 认下的键，其余返回 false 交回 AppKit。
    func handlePreDispatchKey(_ event: NSEvent) -> Bool {
        guard panel.isVisible else { return false }
        let press = PanelKeyPress(event)
        let context = keyContext.context()

        // 按了非 ⌘+数字 的键：编号提示立刻收起，避免 ⌘C 等组合闪一下。
        if press.quickPasteOffset == nil {
            quickPasteHintState.cancel()
        }

        guard case .panel(let action) = PanelKeyRouter.route(press, context: context) else {
            return false
        }
        return apply(action)
    }

    /// 只认 ⌘ / ⌘⇧；预览、编辑、菜单弹出时编号不出现。
    func handleModifierFlagsChanged(_ event: NSEvent) {
        let context = keyContext.context()
        guard panel.isKeyWindow,
              !context.isModalPresented,
              !context.isIMEComposing,
              context.canQuickPasteVisibleRow else {
            quickPasteHintState.cancel()
            return
        }
        quickPasteHintState.handleModifiers(event.modifierFlags)
    }

    /// 先走原生菜单 key equivalent；菜单栏不可用时再走菜单索引 fallback。
    func handleCommandKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }

        let command = menuCommands.command(for: event)

        // 预览或文本输入中，⌥⌘F 不该把焦点塞给被盖住的搜索框。
        if let command,
           command.action == #selector(ClipboardPanelController.focusSearch(_:)),
           previewState.item != nil || isTextEditing {
            return false
        }

        // 只读文本预览的 ⌘V 由 PreviewTextView 处理；PDF/Web 预览没有这层兜底。
        if let command,
           command.action == #selector(NSText.paste(_:)),
           previewState.item != nil,
           !isTextEditing,
           !(panel.firstResponder is PreviewTextView) {
            pasteSelectedItem()
            return true
        }

        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }

        return command?.performValidated() ?? false
    }

    /// 富文本编辑、搜索框、查找栏或组筛选框聚焦；命令归文本响应链。
    private var isTextEditing: Bool {
        previewState.isEditing
            || searchState.isFocused
            || previewSurface.isFindBarVisible
            || previewSurface.isFocusedOnGroupFilter
    }

    func shouldUseDefaultKeyDown(for event: NSEvent) -> Bool {
        moreActionsState.isFocused && event.keyCode == PanelKeyCode.space
    }

    /// 更多操作聚焦时，Space 交给 AppKit 默认 keyDown，让 SwiftUI Menu 自己开菜单。

    /// 预览中、输入法组合或有模态时，Tab 交给系统。
    var shouldCycleFocusWithTab: Bool {
        guard previewState.item == nil else { return false }
        guard !confirmationState.isPresenting, panel.attachedSheet == nil else { return false }
        return !isIMEComposing
    }

    func cycleFocus(backwards: Bool) {
        focusZones.cycle(backwards: backwards)
    }

    private var isIMEComposing: Bool {
        (panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    // MARK: - 标准 action（interpretKeyEvents 的落点）

    @objc func moveUp(_ sender: Any?) {
        if let item = previewState.item, item.kind == .file, item.fileCount > 1,
           previewState.groupFileIndex == nil,
           previewState.moveGroupSelection(by: -1, visibleIndices: previewState.visibleGroupFileIndices) {
            return
        }
        if previewState.item != nil {
            cursor.stepPreview(direction: -1)
            return
        }
        if let first = store.rows.first, cursor.selectedItemID == first.id {
            focusZones.focusSearch()
            return
        }
        cursor.move(direction: -1)
    }

    @objc func moveDown(_ sender: Any?) {
        if let item = previewState.item, item.kind == .file, item.fileCount > 1,
           previewState.groupFileIndex == nil,
           previewState.moveGroupSelection(by: 1, visibleIndices: previewState.visibleGroupFileIndices) {
            return
        }
        if previewState.item != nil {
            cursor.stepPreview(direction: 1)
            return
        }
        cursor.move(direction: 1)
    }

    /// 空实现避免标准 action 落到响应链末尾时响系统提示音；←/→ 交给内容自己处理。
    @objc func moveLeft(_ sender: Any?) {}
    @objc func moveRight(_ sender: Any?) {}

    @objc func moveToBeginningOfDocument(_ sender: Any?) {
        if previewState.item != nil {
            cursor.jumpPreview(to: 0)
        } else {
            cursor.jumpToBeginning()
        }
    }

    @objc func moveToEndOfDocument(_ sender: Any?) {
        if previewState.item != nil {
            cursor.jumpPreviewToOldest()
        } else {
            cursor.jumpToOldest()
        }
    }

    @objc func insertNewline(_ sender: Any?) {
        if let item = previewState.item, item.kind == .file, item.fileCount > 1,
           let index = previewState.focusedGroupFileIndex {
            pasteFlow.paste(item, fileIndex: index)
            return
        }
        guard let item = currentLightItem, let full = fullItem(id: item.id) else { return }
        pasteFlow.paste(full)
    }

    @objc func insertTab(_ sender: Any?) {
        panel.selectNextKeyView(nil)
    }

    @objc func insertBacktab(_ sender: Any?) {
        panel.selectPreviousKeyView(nil)
    }

    @objc func deleteBackward(_ sender: Any?) {
        deleteSelectedItem()
    }

    /// 执行判定出的动作。返回 false 表示这一步没做成，事件继续交给 AppKit。
    private func apply(_ action: PanelKeyAction) -> Bool {
        switch action {
        case .consume:
            break

        case .hidePanel:
            hide()
        case .cycleFocus(let backwards):
            focusZones.cycle(backwards: backwards)

        case .focusSearch:
            focusZones.focusSearch()

        case .escape:
            handleEscape()
        case .cancelEditing:
            requestCancelEditing()
        case .dismissPreviewFindBar:
            closePreviewFindBar()
        case .performPreviewFindCommand(let command):
            guard performPreviewFindCommand(command) else { return false }
        case .openPreviewForSelection:
            if let selectedID = cursor.selectedItemID, let item = fullItem(id: selectedID) {
                previewLauncher.present(item)
            }
        case .closePreview:
            previewState.close()

        case .activateSelectedItem(let asPlainText):
            activateSelected(asPlainText: asPlainText)
        case .activateFocusedGroupFile(let index):
            if let item = previewState.item { pasteFlow.paste(item, fileIndex: index) }
        case .pasteVisibleRow(let offset, let asPlainText):
            pasteVisibleRow(offset: offset, asPlainText: asPlainText)

        case .stepPreview(let delta):
            cursor.stepPreview(direction: delta)
        case .jumpPreview(let index):
            cursor.jumpPreview(to: index)
        case .jumpPreviewToOldest:
            cursor.jumpPreviewToOldest()
        case .moveGroupSelection(let delta):
            previewState.moveGroupSelection(by: delta, visibleIndices: previewState.visibleGroupFileIndices)
        case .jumpGroupSelection(let toFirst):
            previewState.jumpGroupSelection(toFirst: toFirst, visibleIndices: previewState.visibleGroupFileIndices)
        case .stepGroupFile(let delta):
            previewState.stepGroupFile(delta: delta, visibleIndices: previewState.visibleGroupFileIndices)
        case .jumpGroupFile(let toFirst):
            previewState.jumpGroupFile(toFirst: toFirst, visibleIndices: previewState.visibleGroupFileIndices)
        case .showGroupFile(let index):
            previewState.showGroupFile(index)
        case .showGroupOverview:
            previewState.showGroupOverview()
        case .focusGroupFilter:
            searchState.resignFocus()
            previewState.focusGroupFilter()
        case .focusGroupList:
            previewState.moveFromGroupFilterToList()
            panel.makeFirstResponder(panel.contentView)
        }
        return true
    }

    private func removeMonitors() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
    }
}
