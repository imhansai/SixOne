//
//  PanelContext.swift
//  SixOne

import AppKit
import Foundation

/// 条目级动作：粘贴、删除、复制、打开、分享与缩略图刷新。
protocol ItemActionHandling: AnyObject {
    func panelDidActivate(id: UUID, asPlainText: Bool)
    func panelDidPasteAsPlainText(id: UUID)
    func panelDidRequestDelete(id: UUID)
    func panelDidRequestOpen(id: UUID)
    func panelDidRequestReveal(id: UUID)
    /// 复制图片并交给 Shottr 从剪贴板加载。
    func panelDidRequestOpenInShottr(id: UUID)
    func panelDidRequestShare(id: UUID, anchorView: NSView)
    /// 复制指定条目回剪贴板；反馈由调用方负责。
    func panelDidRequestCopy(id: UUID)
    /// 只复制指定条目的纯文本形态。
    func panelDidRequestCopyAsPlainText(id: UUID)
    /// 复制一段不属于历史条目的文字（路径、标题、色值）。
    func panelDidRequestCopyText(_ text: String)
    /// 旧尺寸缩略图按当前尺寸重算。
    func panelDidRequestThumbnailRefresh(id: UUID)
    /// 添加或编辑条目别名；`currentAlias` 由调用方提供，避免再次查库。
    func panelDidRequestEditAlias(id: UUID, currentAlias: String?)
    /// 把条目移到指定分组；nil 表示未分组。
    func panelDidRequestAssignCollection(itemID: UUID, collectionID: UUID?)
    /// 新建分组并把当前条目移进去。
    func panelDidRequestNewCollection(assigningItemID: UUID)
}

/// 预览编辑：退出、取消与保存。
protocol EditingActionHandling: AnyObject {
    func panelDidRequestEscape()
    func panelDidRequestCancelEditing()
    /// 保存预览里的编辑结果并写回剪贴板。
    func panelDidRequestSaveEditedText(id: UUID, text: String, richText: Data?)
}

/// 搜索框出站动作。
protocol SearchActionHandling: AnyObject {
    func panelDidRequestSearchCancel()
    /// 先把防抖期未落库的词应用掉，再进列表。
    func panelDidRequestSearchMoveDown()
    func panelDidRequestSearchTab(backwards: Bool)
}

/// 多文件组的分享与组内文件命令。
protocol GroupActionHandling: AnyObject {
    func panelDidRequestGroupFileShare(at index: Int, anchorView: NSView)
    func panelDidRequestShareGroup(anchorView: NSView?)
    func panelDidInvokeGroupFileCommand(_ command: GroupFileCommand, index: Int)
}

/// 用户分组的新建、重命名与删除。
protocol CollectionActionHandling: AnyObject {
    func panelDidRequestCreateCollection()
    func panelDidRequestRenameCollection(id: UUID)
    func panelDidRequestDeleteCollection(id: UUID)
}

/// 筛选弹层：应用或清除四区筛选。
protocol FilterActionHandling: AnyObject {
    func panelDidRequestHistoryFilter(_ filter: HistoryFilter)
    func panelDidRequestClearHistoryFilters()
}

/// 面板外壳：设置入口、交棒外部应用、交还内容焦点与清空历史。
protocol ShellActionHandling: AnyObject {
    /// 是否接上了设置入口；没接上时「更多操作」不显示该项。
    var canRequestSettings: Bool { get }
    func panelDidRequestSettings()
    /// 已交给外部应用：收起面板且不抢回原应用焦点。
    func panelDidHandOffToExternalApp()
    func panelDidRequestFocusContent()
    func panelDidRequestClearHistory()
    /// 系统筛选 popover 关闭后重新按焦点决定面板是否收起。
    func panelDidDismissFilterPopover()
}

/// 面板动作的完整集合；控制器实现它，视图只依赖上面用得到的窄协议。
protocol PanelActionHandler: ItemActionHandling, EditingActionHandling, SearchActionHandling,
    GroupActionHandling, CollectionActionHandling, FilterActionHandling, ShellActionHandling {}

@Observable
final class PanelContext {
    let manager: ClipboardManager
    let store: HistoryListStore
    let caches: PanelCaches
    /// 分组列表；测试可省略。
    let collections: CollectionListStore?
    /// 筛选弹层的来源候选；面板唤出时刷新。
    let filterSources: FilterSourceCatalog

    let panelState = PanelState()
    let confirmationState = ConfirmationState()
    let searchState = SearchState()
    let moreActionsState = MoreActionsState()
    let filterState = FilterState()
    let previewState = PreviewState()
    let navigationState = NavigationState()
    let copyState = CopyState()
    let noticeState = NoticeState()
    /// 按住 ⌘ 时显示快速粘贴编号。
    let quickPasteHintState = QuickPasteHintState()
    let shareState = ShareState()
    /// 列表滚动条形态：`HistoryListTableView` 发布、行视图读取。
    let scrollerLayout = ScrollerLayoutState()
    /// 搜索词到库查询链路：输入变化、Esc 清空与唤出对齐。
    let searchSession: PanelSearchSession
    /// 菜单校验用的文件能力缓存：校验只读，解析在后台。
    let fileCapabilities: PanelFileCapabilityCache

    /// 面板级动作的实现方；控制器在 init 里认领。
    weak var actions: PanelActionHandler?

    /// 各视图按需取用的窄接口，避免拿到整张动作表。
    var itemActions: ItemActionHandling? { actions }
    var editingActions: EditingActionHandling? { actions }
    var searchActions: SearchActionHandling? { actions }
    var groupActions: GroupActionHandling? { actions }
    var collectionActions: CollectionActionHandling? { actions }
    var filterActions: FilterActionHandling? { actions }
    var shellActions: ShellActionHandling? { actions }

    init(
        manager: ClipboardManager,
        store: HistoryListStore,
        caches: PanelCaches,
        collections: CollectionListStore? = nil
    ) {
        self.manager = manager
        self.store = store
        self.caches = caches
        self.collections = collections
        self.filterSources = FilterSourceCatalog(store: store)
        self.fileCapabilities = PanelFileCapabilityCache(
            onBookmarksRefreshed: { [weak manager] itemID, refreshes in
                manager?.refreshSecurityScopeBookmarks(id: itemID, refreshes)
            }
        )
        self.searchSession = PanelSearchSession(
            store: store,
            searchState: searchState,
            navigationState: navigationState
        )
    }
}

/// 视图侧的统一意图入口：有控制器时交给它，独立预览/测试没有接线时直接落回 manager。
extension PanelContext {
    func copyItem(id: UUID) {
        if let itemActions {
            itemActions.panelDidRequestCopy(id: id)
        } else {
            manager.copy(id: id)
        }
    }

    func copyItemAsPlainText(id: UUID) {
        if let itemActions {
            itemActions.panelDidRequestCopyAsPlainText(id: id)
        } else {
            manager.copyAsPlainText(id: id)
        }
    }

    func copyText(_ text: String) {
        if let itemActions {
            itemActions.panelDidRequestCopyText(text)
        } else {
            manager.copyPlainText(text)
        }
    }

    func saveEditedText(id: UUID, text: String, richText: Data?) {
        if let editingActions {
            editingActions.panelDidRequestSaveEditedText(id: id, text: text, richText: richText)
        } else {
            manager.updateEditedText(id: id, text: text, richText: richText)
        }
    }
}
