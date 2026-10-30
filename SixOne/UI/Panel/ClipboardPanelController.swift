//
//  ClipboardPanelController.swift
//  SixOne
//  面板控制器：面板级动作、菜单命令与键盘执行；窗口生命周期在 `PanelWindowLifecycle`。

import AppKit
import SwiftUI

/// 剪贴板面板控制：面板级动作、菜单命令与键盘 action。
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

    var onOpenSettings: (() -> Void)?

    private var hostingController: NSViewController?

    /// 窗口显示/收起、定位、会话恢复与焦点判定。
    private lazy var lifecycle = PanelWindowLifecycle(
        panel: panel,
        manager: manager,
        store: store,
        panelState: panelState,
        confirmationState: confirmationState,
        searchState: searchState,
        moreActionsState: moreActionsState,
        previewState: previewState,
        navigationState: navigationState,
        noticeState: noticeState,
        shareState: shareState,
        quickPasteHintState: quickPasteHintState,
        cursor: cursor,
        sharing: sharing
    )

    private lazy var itemActions = PanelItemActions(
        manager: manager,
        store: store,
        panel: panel,
        previewState: previewState,
        navigationState: navigationState,
        copyState: copyState,
        noticeState: noticeState,
        confirmationState: confirmationState,
        cursor: cursor,
        previewLauncher: previewLauncher,
        pasteFlow: pasteFlow,
        sharing: sharing,
        handOff: { [weak self] in
            self?.lifecycle.hide(restoresPreviousApplication: false)
        }
    )

    private lazy var editingSession = PanelEditingSession(
        panel: panel,
        previewState: previewState,
        confirmationState: confirmationState,
        moreActionsState: moreActionsState,
        hide: { [weak self] in self?.lifecycle.hide() }
    )

    private lazy var keyExecutor = PanelKeyActionExecutor(
        panel: panel,
        itemActions: itemActions,
        editingSession: editingSession,
        cursor: cursor,
        previewState: previewState,
        previewLauncher: previewLauncher,
        pasteFlow: pasteFlow,
        focusZones: focusZones,
        searchState: searchState,
        hide: { [weak self] in self?.lifecycle.hide() },
        fullItem: { [weak self] id in self?.manager.fetchFullItem(id: id) }
    )

    var positionProvider: (() -> NSRect?)? {
        get { lifecycle.positionProvider }
        set { lifecycle.positionProvider = newValue }
    }

    /// 收起那一拍摘掉设置窗口的 key/main 候选，收完恢复（未建窗口时无需做事）。
    var setSettingsKeyAndMainSuspended: ((_ suspended: Bool) -> Void)? {
        get { lifecycle.setSettingsKeyAndMainSuspended }
        set { lifecycle.setSettingsKeyAndMainSuspended = newValue }
    }
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
        previousApplication: { [weak self] in self?.lifecycle.previousApplicationForPaste },
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
            guard let range = self?.quickPasteVisibleRange else { return 0 }
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

        // 沿用之前的时机：控制器构造时就装好焦点/激活监听。
        _ = lifecycle
    }

    private func makeRootView() -> some View {
        ClipboardListView(context: context)
            .environment(context)
            .environment(\.locale, RuntimeLanguage.shared.locale)
            .environment(RuntimeLanguage.shared)
    }

    // MARK: - 面板级动作（PanelActionHandler）

    func panelDidActivate(id: UUID, asPlainText: Bool) {
        itemActions.activate(id: id, asPlainText: asPlainText)
    }

    func panelDidRequestDelete(id: UUID) {
        itemActions.requestDelete(id: id)
    }

    func panelDidPasteAsPlainText(id: UUID) {
        itemActions.pasteAsPlainText(id: id)
    }

    func panelDidRequestOpen(id: UUID) {
        itemActions.requestOpen(id: id)
    }

    var canRequestSettings: Bool { onOpenSettings != nil }

    func panelDidRequestSettings() {
        onOpenSettings?()
    }

    func panelDidHandOffToExternalApp() {
        hide(restoresPreviousApplication: false)
    }

    func panelDidRequestShare(id: UUID, anchorView: NSView) {
        itemActions.requestShare(id: id, anchorView: anchorView)
    }

    func panelDidRequestFocusContent() {
        previewState.releaseGroupFilterFocus()
        panel.makeFirstResponder(panel.contentView)
    }

    func panelDidRequestGroupFileShare(at index: Int, anchorView: NSView) {
        itemActions.requestGroupFileShare(at: index, anchorView: anchorView)
    }

    func panelDidRequestShareGroup(anchorView: NSView?) {
        itemActions.requestShareGroup(anchorView: anchorView)
    }

    func panelDidInvokeGroupFileCommand(_ command: GroupFileCommand, index: Int) {
        itemActions.invokeGroupFileCommand(command, index: index)
    }

    func panelDidRequestEscape() {
        editingSession.handleEscape()
    }

    func panelDidRequestCancelEditing() {
        editingSession.requestCancelEditing()
    }

    func panelDidRequestCopyItem() {
        itemActions.copySelectedItem()
    }

    func panelDidRequestPasteItem() {
        itemActions.pasteSelectedItem()
    }

    func panelDidRequestCopy(id: UUID) {
        itemActions.copyItem(id: id)
    }

    func panelDidRequestCopyAsPlainText(id: UUID) {
        itemActions.copyItemAsPlainText(id: id)
    }

    func panelDidRequestCopyText(_ text: String) {
        itemActions.copyText(text)
    }

    func panelDidRequestSaveEditedText(id: UUID, text: String, richText: Data?) {
        itemActions.saveEditedText(id: id, text: text, richText: richText)
    }

    func panelDidRequestThumbnailRefresh(id: UUID) {
        itemActions.refreshThumbnail(id: id)
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

    func toggle(anchor: PanelAnchor) {
        lifecycle.toggle(anchor: anchor)
    }

    func show(anchor: PanelAnchor) {
        lifecycle.show(anchor: anchor)
    }

    func handleCloseWindow() {
        if previewState.isEditing {
            editingSession.requestCancelEditing()
        } else {
            hide()
        }
    }

    func hide(restoresPreviousApplication: Bool = true) {
        lifecycle.hide(restoresPreviousApplication: restoresPreviousApplication)
    }

    func handleQuitAttempt() -> Bool {
        editingSession.handleQuitAttempt()
    }

    func handleEscape() {
        editingSession.handleEscape()
    }

    // MARK: - 菜单命令

    private var commandAvailability: PanelCommandAvailability {
        let item = itemActions.currentItem
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
        itemActions.copySelectedItem()
    }

    @objc func paste(_ sender: Any?) {
        itemActions.pasteSelectedItem()
    }

    @objc func copyAsPlainText(_ sender: Any?) {
        itemActions.copyAsPlainTextForCurrentItem()
    }

    @objc func pasteAsPlainText(_ sender: Any?) {
        itemActions.pasteAsPlainTextForCurrentItem()
    }

    @objc func delete(_ sender: Any?) {
        itemActions.deleteSelectedItem()
    }

    @objc func previewSelectedItem(_ sender: Any?) {
        itemActions.previewCurrentItem()
    }

    /// ⌘S：保存当前正文，但保持编辑态；「完成」才退出编辑。
    @objc func saveEditing(_ sender: Any?) {
        previewState.requestSave()
    }

    @objc func openSelectedItem(_ sender: Any?) {
        itemActions.openCurrentItem()
    }

    @objc func revealSelectedItem(_ sender: Any?) {
        itemActions.revealCurrentItem()
    }

    @objc func shareSelectedItem(_ sender: Any?) {
        itemActions.shareCurrentItem()
    }

    @objc func clearHistory(_ sender: Any?) {
        itemActions.requestClearHistory()
    }

    func panelDidRequestClearHistory() {
        itemActions.requestClearHistory()
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
        if let textView = editingSession.previewSurface.previewTextView() {
            textView.performTextFinderAction(sender)
            return
        }
        if sender.tag == NSTextFinder.Action.showFindInterface.rawValue {
            focusZones.focusSearch()
        }
    }

    /// 组总览取组内列表，其余取历史列表。
    private var quickPasteVisibleRange: ClosedRange<Int>? {
        previewState.isGroupOverview ? previewState.groupVisibleRowRange : navigationState.fullyVisibleRange
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
            return editingSession.previewSurface.previewTextView() != nil
        default:
            return false
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
        return keyExecutor.apply(action)
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
            itemActions.pasteSelectedItem()
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
            || editingSession.previewSurface.isFindBarVisible
            || editingSession.previewSurface.isFocusedOnGroupFilter
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
        itemActions.pasteSelectedItem()
    }

    @objc func insertTab(_ sender: Any?) {
        panel.selectNextKeyView(nil)
    }

    @objc func insertBacktab(_ sender: Any?) {
        panel.selectPreviousKeyView(nil)
    }

    @objc func deleteBackward(_ sender: Any?) {
        itemActions.deleteSelectedItem()
    }

    /// 外接键盘的 Delete（⌦），与 Backspace 相同。
    @objc func deleteForward(_ sender: Any?) {
        itemActions.deleteSelectedItem()
    }

}
