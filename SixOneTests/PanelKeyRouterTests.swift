//
//  PanelKeyRouterTests.swift
//  SixOneTests
//  窗口级 pre-dispatch 路由：面板只接少数键，其余交回 AppKit。

import AppKit
import Carbon.HIToolbox
import Testing
@testable import SixOne

@Suite("面板 pre-dispatch 路由")
struct PanelKeyRouterTests {
    private func route(
        _ key: UInt16,
        _ modifiers: NSEvent.ModifierFlags = [],
        _ context: PanelKeyContext = PanelKeyContext()
    ) -> PanelKeyRoute {
        PanelKeyRouter.route(
            PanelKeyPress(keyCode: key, modifiers: modifiers),
            context: context
        )
    }

    @Test("模态与输入法：所有键走标准路径")
    func modalAndIME() {
        var modal = PanelKeyContext()
        modal.isModalPresented = true
        #expect(route(PanelKeyCode.escape, [], modal) == .standard)
        #expect(route(PanelKeyCode.down, [], modal) == .standard)

        var composing = PanelKeyContext(isIMEComposing: true)
        composing.isSearchFocused = true
        #expect(route(PanelKeyCode.escape, [], composing) == .standard)
    }

    @Test("Tab：列表/搜索/更多操作都走焦点循环；预览中走标准")
    func tabRouting() {
        #expect(route(PanelKeyCode.tab) == .panel(.cycleFocus(backwards: false)))
        #expect(route(PanelKeyCode.tab, .shift) == .panel(.cycleFocus(backwards: true)))
        #expect(route(PanelKeyCode.tab, [], PanelKeyContext(isSearchFocused: true))
            == .panel(.cycleFocus(backwards: false)))
        #expect(route(PanelKeyCode.tab, [], PanelKeyContext(previewKind: .text)) == .standard)
    }

    @Test("Control+Tab 是 HIG 的组间切换：与 Tab 一样走焦点循环")
    func controlTabCyclesFocus() {
        #expect(route(PanelKeyCode.tab, .control) == .panel(.cycleFocus(backwards: false)))
        #expect(route(PanelKeyCode.tab, [.control, .shift]) == .panel(.cycleFocus(backwards: true)))

        #expect(route(PanelKeyCode.tab, .control, PanelKeyContext(previewKind: .text)) == .standard)

        let repeated = PanelKeyPress(keyCode: PanelKeyCode.tab, modifiers: .control, isARepeat: true)
        #expect(PanelKeyRouter.route(repeated, context: PanelKeyContext()) == .panel(.consume))
    }

    @Test("更多操作聚焦：Esc 收面板，导航键吞掉，Space 放行")
    func moreActions() {
        let context = PanelKeyContext(isMoreActionsFocused: true)
        #expect(route(PanelKeyCode.escape, [], context) == .panel(.hidePanel))
        #expect(route(PanelKeyCode.up, [], context) == .panel(.consume))
        #expect(route(PanelKeyCode.down, [], context) == .panel(.consume))
        #expect(route(PanelKeyCode.returnKey, [], context) == .panel(.consume))
        #expect(route(PanelKeyCode.returnKey, .shift, context) == .panel(.consume),
                "菜单聚焦时 ⇧+Return 不该粘贴")
        #expect(route(PanelKeyCode.delete, [], context) == .panel(.consume))
        #expect(route(PanelKeyCode.up, .command, context) == .panel(.consume))
        #expect(route(PanelKeyCode.space, [], context) == .standard)
    }

    @Test("搜索框：⌘F 与 ↑/⌘↑/⌘↓ 吞掉，Esc/↓/Return 交给 delegate")
    func searchField() {
        let context = PanelKeyContext(isSearchFocused: true)
        #expect(route(PanelKeyCode.f, .command, context) == .panel(.consume))
        #expect(route(PanelKeyCode.up, [], context) == .panel(.consume))
        #expect(route(PanelKeyCode.up, .command, context) == .panel(.consume))
        #expect(route(PanelKeyCode.down, .command, context) == .panel(.consume))

        #expect(route(PanelKeyCode.escape, [], context) == .standard)
        #expect(route(PanelKeyCode.down, [], context) == .standard)
        #expect(route(PanelKeyCode.returnKey, [], context) == .standard)
    }

    @Test("查找栏：Esc 关栏，查找命令转交文本视图，其余放行")
    func findBar() {
        var context = PanelKeyContext(previewKind: .text)
        context.isPreviewFindBarVisible = true
        #expect(route(PanelKeyCode.escape, [], context) == .panel(.dismissPreviewFindBar))
        #expect(route(PanelKeyCode.f, .command, context)
            == .panel(.performPreviewFindCommand(.showFindInterface)))
        #expect(route(PanelKeyCode.g, .command, context)
            == .panel(.performPreviewFindCommand(.nextMatch)))
        #expect(route(PanelKeyCode.down, [], context) == .standard)
    }

    @Test("编辑态：Esc 取消编辑，其余交给 NSTextView；面板非 key 时不抢 Esc")
    func editing() {
        var context = PanelKeyContext(previewKind: .text)
        context.isEditing = true
        #expect(route(PanelKeyCode.escape, [], context) == .panel(.cancelEditing))
        #expect(route(PanelKeyCode.left, [], context) == .standard)

        context.isPanelKeyWindow = false
        #expect(route(PanelKeyCode.escape, [], context) == .standard)
    }

    @Test("只读文本预览聚焦：查找、全选、有选区的 ⌘C 放行")
    func previewTextFocused() {
        var context = PanelKeyContext(previewKind: .text, hasPreviewTextSelection: true)
        context.isPreviewTextFocused = true
        #expect(route(PanelKeyCode.f, .command, context) == .standard)
        #expect(route(PanelKeyCode.g, .command, context) == .standard)
        #expect(route(PanelKeyCode.a, .command, context) == .standard)
        #expect(route(PanelKeyCode.c, .command, context) == .standard)

        context.hasPreviewTextSelection = false
        #expect(route(PanelKeyCode.c, .command, context) == .standard,
                "无选区时也走标准路径，由 PreviewTextView.copy 兜底")
    }

    @Test("文件组：列表内移动、到边缘停住；查看态用 ↑/↓ 换文件，Esc/Space 退列表")
    func fileGroup() {
        var list = PanelKeyContext(previewKind: .file, previewFileCount: 4)
        list.canMoveGroupSelectionUp = true
        list.canMoveGroupSelectionDown = true
        #expect(route(PanelKeyCode.up, [], list) == .panel(.moveGroupSelection(by: -1)))
        #expect(route(PanelKeyCode.down, [], list) == .panel(.moveGroupSelection(by: 1)))
        #expect(route(PanelKeyCode.left, [], list) == .panel(.consume))
        #expect(route(PanelKeyCode.right, [], list) == .panel(.consume))
        #expect(route(PanelKeyCode.f, .command, list) == .panel(.focusGroupFilter))
        #expect(route(PanelKeyCode.tab, [], list) == .panel(.focusGroupFilter))
        #expect(route(PanelKeyCode.tab, .shift, list) == .panel(.focusGroupFilter))
        #expect(route(PanelKeyCode.tab, .control, list) == .panel(.focusGroupFilter))
        #expect(route(PanelKeyCode.tab, [.control, .shift], list) == .panel(.focusGroupFilter))
        #expect(route(PanelKeyCode.up, .command, list) == .panel(.jumpGroupSelection(toFirst: true)))
        #expect(route(PanelKeyCode.down, .command, list) == .panel(.jumpGroupSelection(toFirst: false)))

        list.focusedGroupFileIndex = 2
        #expect(route(PanelKeyCode.space, [], list) == .panel(.showGroupFile(index: 2)))
        list.focusedGroupFileIndex = nil
        #expect(route(PanelKeyCode.space, [], list) == .panel(.closePreview))

        list.canMoveGroupSelectionUp = false
        list.canMoveGroupSelectionDown = false
        #expect(route(PanelKeyCode.up, [], list) == .panel(.consume),
                "没有选中时到列表头就停住，不再切外层历史条目")
        #expect(route(PanelKeyCode.down, [], list) == .panel(.consume))

        list.focusedGroupFileIndex = 0
        #expect(route(PanelKeyCode.up, [], list) == .panel(.focusGroupFilter))
        list.focusedGroupFileIndex = nil

        var viewing = PanelKeyContext(previewKind: .file, previewFileCount: 4)
        viewing.isViewingGroupFile = true
        viewing.focusedGroupFileIndex = 1
        #expect(route(PanelKeyCode.up, [], viewing) == .panel(.stepGroupFile(by: -1)))
        #expect(route(PanelKeyCode.down, [], viewing) == .panel(.stepGroupFile(by: 1)))
        #expect(route(PanelKeyCode.up, .command, viewing) == .panel(.jumpGroupFile(toFirst: true)))
        #expect(route(PanelKeyCode.down, .command, viewing) == .panel(.jumpGroupFile(toFirst: false)))
        #expect(route(PanelKeyCode.left, [], viewing) == .standard, "查看态不再用左右键换文件")
        #expect(route(PanelKeyCode.right, [], viewing) == .standard)
        #expect(route(PanelKeyCode.space, [], viewing) == .panel(.showGroupOverview))
        #expect(route(PanelKeyCode.escape, [], viewing) == .panel(.showGroupOverview))
    }

    @Test("文件组筛选框聚焦：⌘F 幂等聚焦，↑ 吞掉，其余交给 SearchField")
    func groupFilterFocused() {
        var context = PanelKeyContext(previewKind: .file, previewFileCount: 4)
        context.isGroupFilterFocused = true

        #expect(route(PanelKeyCode.f, .command, context) == .panel(.focusGroupFilter),
                "⌘F 幂等聚焦，不在筛选框分支里被吞")
        #expect(route(PanelKeyCode.tab, [], context) == .panel(.focusGroupList))
        #expect(route(PanelKeyCode.tab, .shift, context) == .panel(.focusGroupList))
        #expect(route(PanelKeyCode.tab, .control, context) == .panel(.focusGroupList))
        #expect(route(PanelKeyCode.tab, [.control, .shift], context) == .panel(.focusGroupList))
        #expect(route(PanelKeyCode.up, [], context) == .panel(.consume))
        #expect(route(PanelKeyCode.up, .command, context) == .panel(.consume))
        #expect(route(PanelKeyCode.down, .command, context) == .panel(.consume))
        #expect(route(PanelKeyCode.a, [], context) == .standard)
        #expect(route(PanelKeyCode.space, [], context) == .standard)
        #expect(route(PanelKeyCode.escape, [], context) == .standard)
        #expect(route(PanelKeyCode.down, [], context) == .standard)
        #expect(route(PanelKeyCode.returnKey, [], context) == .standard)
    }

    @Test("预览：方向、Space、Return、Esc、⌘↑/⌘↓、⌘F 在响应链之前接管")
    func previewKeys() {
        let context = PanelKeyContext(previewKind: .file, previewFileCount: 1, hasSelection: true)
        #expect(route(PanelKeyCode.escape, [], context) == .panel(.escape))
        #expect(route(PanelKeyCode.space, [], context) == .panel(.closePreview))
        #expect(route(PanelKeyCode.returnKey, [], context)
            == .panel(.activateSelectedItem(asPlainText: false)))
        #expect(route(PanelKeyCode.up, [], context) == .panel(.stepPreview(by: -1)))
        #expect(route(PanelKeyCode.down, [], context) == .panel(.stepPreview(by: 1)))
        #expect(route(PanelKeyCode.up, .command, context) == .panel(.jumpPreview(to: 0)))
        #expect(route(PanelKeyCode.down, .command, context) == .panel(.jumpPreviewToOldest))
        #expect(route(PanelKeyCode.f, .command, context) == .panel(.consume))
    }

    @Test("⇧+Return：粘贴为纯文本；列表与预览都接管，⌘⇧ 与搜索框放行")
    func plainTextReturn() {
        let list = PanelKeyContext(hasSelection: true)
        #expect(route(PanelKeyCode.returnKey, .shift, list)
            == .panel(.activateSelectedItem(asPlainText: true)))
        #expect(route(PanelKeyCode.keypadEnter, .shift, list)
            == .panel(.activateSelectedItem(asPlainText: true)))
        #expect(route(PanelKeyCode.returnKey, .shift) == .panel(.consume),
                "无选中时吞掉，不落到响应链")

        #expect(route(PanelKeyCode.returnKey, [], list) == .standard,
                "不带 Shift 的 Return 仍走 insertNewline")
        #expect(route(PanelKeyCode.returnKey, [.shift, .command], list) == .standard,
                "⌘⇧+Return 不是纯文本粘贴")
        #expect(route(PanelKeyCode.returnKey, .shift, PanelKeyContext(isSearchFocused: true))
            == .standard, "搜索框聚焦时 Return 交给 delegate")

        let preview = PanelKeyContext(previewKind: .text, hasSelection: true)
        #expect(route(PanelKeyCode.returnKey, .shift, preview)
            == .panel(.activateSelectedItem(asPlainText: true)))
    }

    @Test("文本预览聚焦时 ⌘F 放行给查找栏")
    func previewFindWhenTextFocused() {
        var context = PanelKeyContext(previewKind: .text)
        context.isPreviewTextFocused = true
        #expect(route(PanelKeyCode.f, .command, context) == .standard)
    }

    @Test("key repeat：Space/Tab/Esc 的重复不重复触发，方向键保留")
    func keyRepeat() {
        let space = PanelKeyPress(keyCode: PanelKeyCode.space, isARepeat: true)
        #expect(PanelKeyRouter.route(space, context: PanelKeyContext(hasSelection: true))
            == .panel(.consume))

        let tab = PanelKeyPress(keyCode: PanelKeyCode.tab, isARepeat: true)
        #expect(PanelKeyRouter.route(tab, context: PanelKeyContext()) == .panel(.consume))

        let preview = PanelKeyContext(previewKind: .text)
        let esc = PanelKeyPress(keyCode: PanelKeyCode.escape, isARepeat: true)
        #expect(PanelKeyRouter.route(esc, context: preview) == .panel(.consume))

        let down = PanelKeyPress(keyCode: PanelKeyCode.down, isARepeat: true)
        #expect(PanelKeyRouter.route(down, context: preview) == .panel(.stepPreview(by: 1)))
    }

    @Test("⌘+数字：粘贴完整可见行；⌘⇧ 纯文本，越界吞掉，预览/编辑/菜单让路")
    func quickPasteVisibleRows() {
        var list = PanelKeyContext()
        list.visibleRowCount = 5
        #expect(route(PanelKeyCode.one, .command, list)
            == .panel(.pasteVisibleRow(offset: 0, asPlainText: false)))
        #expect(route(PanelKeyCode.three, .command, list)
            == .panel(.pasteVisibleRow(offset: 2, asPlainText: false)))
        #expect(route(PanelKeyCode.two, [.command, .shift], list)
            == .panel(.pasteVisibleRow(offset: 1, asPlainText: true)))
        #expect(route(PanelKeyCode.nine, .command, list) == .panel(.consume),
                "越界数字吞掉，不落到 AppKit 响提示音")
        #expect(route(PanelKeyCode.one, [.command, .option], list) == .standard,
                "⌥⌘+数字不是快速粘贴")
        #expect(route(PanelKeyCode.one, [], list) == .standard)

        let repeated = PanelKeyPress(keyCode: PanelKeyCode.one, modifiers: .command, isARepeat: true)
        #expect(PanelKeyRouter.route(repeated, context: list) == .standard,
                "按住不放不能反复触发粘贴")

        var search = PanelKeyContext(isSearchFocused: true)
        search.visibleRowCount = 3
        #expect(route(PanelKeyCode.one, .command, search)
            == .panel(.pasteVisibleRow(offset: 0, asPlainText: false)),
                "搜索框聚焦时也能直接粘")

        var preview = PanelKeyContext(previewKind: .text)
        preview.visibleRowCount = 3
        #expect(route(PanelKeyCode.one, .command, preview) == .standard)

        var editing = PanelKeyContext(previewKind: .text)
        editing.isEditing = true
        editing.visibleRowCount = 3
        #expect(route(PanelKeyCode.one, .command, editing) == .standard)

        var moreActions = PanelKeyContext(isMoreActionsFocused: true)
        moreActions.visibleRowCount = 3
        #expect(route(PanelKeyCode.one, .command, moreActions) == .standard)
    }

    @Test("文件组总览：⌘+数字粘贴组内可见文件；单文件态与普通预览让路")
    func quickPasteGroupFiles() {
        var group = PanelKeyContext(previewKind: .file, previewFileCount: 4)
        group.visibleRowCount = 3
        #expect(route(PanelKeyCode.one, .command, group)
            == .panel(.pasteVisibleGroupFile(offset: 0, asPlainText: false)))
        #expect(route(PanelKeyCode.two, [.command, .shift], group)
            == .panel(.pasteVisibleGroupFile(offset: 1, asPlainText: true)))
        #expect(route(PanelKeyCode.four, .command, group) == .panel(.consume),
                "越界数字吞掉，不落到 AppKit 响提示音")

        group.isGroupFilterFocused = true
        #expect(route(PanelKeyCode.one, .command, group)
            == .panel(.pasteVisibleGroupFile(offset: 0, asPlainText: false)),
                "组筛选框聚焦时也能直接粘")

        var viewing = PanelKeyContext(previewKind: .file, previewFileCount: 4)
        viewing.isViewingGroupFile = true
        viewing.visibleRowCount = 3
        #expect(route(PanelKeyCode.one, .command, viewing) == .standard,
                "组内单文件态没有编号直粘")

        var single = PanelKeyContext(previewKind: .file, previewFileCount: 1)
        single.visibleRowCount = 3
        #expect(route(PanelKeyCode.one, .command, single) == .standard,
                "单文件条目仍走普通预览，不进入组内快速粘贴")
    }

    @Test("列表：⌘F 是搜索别名，其它命令键交给菜单/响应链")
    func listKeys() {
        #expect(route(PanelKeyCode.f, .command) == .panel(.focusSearch))
        #expect(route(PanelKeyCode.c, .command) == .standard)
        #expect(route(UInt16(kVK_ANSI_V), .command) == .standard)
        #expect(route(PanelKeyCode.c, [.command, .shift]) == .standard)
        #expect(route(UInt16(kVK_ANSI_W), .command) == .standard)
        #expect(route(UInt16(kVK_ANSI_Q), .command) == .standard)
        #expect(route(UInt16(kVK_ANSI_Comma), .command) == .standard)
        #expect(route(PanelKeyCode.returnKey) == .standard)
        #expect(route(PanelKeyCode.space) == .panel(.consume), "无选中时 Space 吞掉")
        #expect(route(PanelKeyCode.space, [], PanelKeyContext(hasSelection: true))
            == .panel(.openPreviewForSelection))
    }
}
