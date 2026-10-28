//
//  PanelKeyRouter.swift
//  SixOne
//  窗口 pre-dispatch 路由：只接管响应链表达不了、又必须保留的键，其余交给 AppKit。

import AppKit

enum PanelKeyRoute: Equatable {
    case panel(PanelKeyAction)
    case standard
}

enum PanelKeyRouter {
    static func route(_ press: PanelKeyPress, context: PanelKeyContext) -> PanelKeyRoute {
        // 模态弹窗与输入法组合：任何键都不抢。
        if context.isModalPresented { return .standard }
        if context.isIMEComposing { return .standard }

        // ⌘+数字直粘完整可见行；搜索框聚焦时同样可用。
        if let offset = press.quickPasteOffset, context.canQuickPasteVisibleRow {
            guard offset < context.visibleRowCount else { return .panel(.consume) }
            return .panel(.pasteVisibleRow(
                offset: offset,
                asPlainText: press.modifiers.contains(.shift)
            ))
        }

        if !context.isPreviewing,
           press.matches(PanelKeyCode.tab, .control)
            || press.matches(PanelKeyCode.tab, [.control, .shift]) {
            return press.isARepeat
                ? .panel(.consume)
                : .panel(.cycleFocus(backwards: press.modifiers.contains(.shift)))
        }

        // Tab 由面板维护循环；完整键盘访问开关在 `PanelFocusZones` 处理。
        if !context.isPreviewing,
           press.matches(PanelKeyCode.tab) || press.matches(PanelKeyCode.tab, .shift) {
            return press.isARepeat
                ? .panel(.consume)
                : .panel(.cycleFocus(backwards: press.modifiers.contains(.shift)))
        }

        // 更多操作聚焦：Esc 收面板，Space 交给 SwiftUI Menu，导航键吞掉。
        if context.isMoreActionsFocused {
            if press.matches(PanelKeyCode.escape) { return .panel(.hidePanel) }
            let navigationKeys = [
                PanelKeyCode.up, PanelKeyCode.down, PanelKeyCode.returnKey,
                PanelKeyCode.keypadEnter, PanelKeyCode.delete,
            ]
            let isNavigation = navigationKeys.contains { press.matches($0) }
                || press.isPlainTextReturn
                || press.matches(PanelKeyCode.up, .command)
                || press.matches(PanelKeyCode.down, .command)
            return isNavigation ? .panel(.consume) : .standard
        }

        // 搜索框：⌘F 吞掉，Esc / ↓ / Return 交给 SearchField 的 delegate。
        if context.isSearchFocused {
            if press.matches(PanelKeyCode.f, .command) { return .panel(.consume) }
            if press.matches(PanelKeyCode.up)
                || press.matches(PanelKeyCode.up, .command)
                || press.matches(PanelKeyCode.down, .command) {
                return .panel(.consume)
            }
            return .standard
        }

        // 文件组筛选框：⌘F 幂等聚焦，Tab 只在筛选框与列表间流转。
        if context.isGroupFilterFocused {
            if press.matches(PanelKeyCode.f, .command) { return .panel(.focusGroupFilter) }
            if Self.isTab(press) {
                return press.isARepeat ? .panel(.consume) : .panel(.focusGroupList)
            }
            if press.matches(PanelKeyCode.up)
                || press.matches(PanelKeyCode.up, .command)
                || press.matches(PanelKeyCode.down, .command) {
                return .panel(.consume)
            }
            return .standard
        }

        // 查找栏：Esc 先关栏，查找命令转交预览文本视图。
        if context.isPreviewFindBarVisible {
            if press.matches(PanelKeyCode.escape) { return .panel(.dismissPreviewFindBar) }
            if let command = press.previewFindCommand {
                return .panel(.performPreviewFindCommand(command))
            }
            return .standard
        }

        // 编辑中 Esc 请求取消（有改动由控制器确认），其余交给 NSTextView。
        if context.isEditing {
            if context.isPanelKeyWindow,
               press.matches(PanelKeyCode.escape),
               !context.isIMEComposing {
                return .panel(.cancelEditing)
            }
            return .standard
        }

        // 只读文本预览聚焦：查找、全选、有选区的 ⌘C 交给 NSTextView。
        if context.isPreviewTextFocused {
            if press.isTextFindingCommand { return .standard }
            if press.matches(PanelKeyCode.a, .command) { return .standard }
            if press.matches(PanelKeyCode.c, .command), context.hasPreviewTextSelection {
                return .standard
            }
        }

        // 文件组预览只在组内导航，不切换外层历史。
        if context.previewKind == .file, context.previewFileCount > 1 {
            let viewing = context.isViewingGroupFile
            if viewing {
                // 单文件态：↑/↓ 换文件，Space / Esc 回总览；←/→ 留给内容本身。
                if press.matches(PanelKeyCode.up, .command) {
                    return .panel(.jumpGroupFile(toFirst: true))
                }
                if press.matches(PanelKeyCode.down, .command) {
                    return .panel(.jumpGroupFile(toFirst: false))
                }
                if press.matches(PanelKeyCode.up) { return .panel(.stepGroupFile(by: -1)) }
                if press.matches(PanelKeyCode.down) { return .panel(.stepGroupFile(by: 1)) }
                if press.matches(PanelKeyCode.space) {
                    return press.isARepeat ? .panel(.consume) : .panel(.showGroupOverview)
                }
                if press.matches(PanelKeyCode.escape) {
                    return press.isARepeat ? .panel(.consume) : .panel(.showGroupOverview)
                }
            } else {
                if press.matches(PanelKeyCode.f, .command) { return .panel(.focusGroupFilter) }
                if Self.isTab(press) {
                    return press.isARepeat ? .panel(.consume) : .panel(.focusGroupFilter)
                }
                if press.matches(PanelKeyCode.left) || press.matches(PanelKeyCode.right) {
                    return .panel(.consume)
                }
                if press.matches(PanelKeyCode.up, .command) {
                    return .panel(.jumpGroupSelection(toFirst: true))
                }
                if press.matches(PanelKeyCode.down, .command) {
                    return .panel(.jumpGroupSelection(toFirst: false))
                }
                // 到首/末行停住；首行再往上回到筛选框。
                if press.matches(PanelKeyCode.up) {
                    if context.canMoveGroupSelectionUp { return .panel(.moveGroupSelection(by: -1)) }
                    if context.focusedGroupFileIndex != nil { return .panel(.focusGroupFilter) }
                    return .panel(.consume)
                }
                if press.matches(PanelKeyCode.down) {
                    return context.canMoveGroupSelectionDown
                        ? .panel(.moveGroupSelection(by: 1))
                        : .panel(.consume)
                }
                if press.matches(PanelKeyCode.space) {
                    guard !press.isARepeat else { return .panel(.consume) }
                    if let index = context.focusedGroupFileIndex {
                        return .panel(.showGroupFile(index: index))
                    }
                    return .panel(.closePreview)
                }
            }
        }

        // 预览：方向、Space、Return、Esc、⌘↑/⌘↓ 在响应链前接管。
        if context.isPreviewing {
            if press.matches(PanelKeyCode.escape) {
                return press.isARepeat ? .panel(.consume) : .panel(.escape)
            }
            if press.matches(PanelKeyCode.space) {
                return press.isARepeat ? .panel(.consume) : .panel(.closePreview)
            }

            if press.matches(PanelKeyCode.returnKey)
                || press.matches(PanelKeyCode.keypadEnter)
                || press.isPlainTextReturn {
                if let index = focusedGroupFileIndex(context) {
                    return .panel(.activateFocusedGroupFile(index: index))
                }
                return .panel(.activateSelectedItem(asPlainText: press.isPlainTextReturn))
            }

            if press.matches(PanelKeyCode.up, .command) {
                return .panel(.jumpPreview(to: 0))
            }
            if press.matches(PanelKeyCode.down, .command) {
                return .panel(.jumpPreviewToOldest)
            }

            if press.matches(PanelKeyCode.f, .command) {
                return context.isPreviewTextFocused ? .standard : .panel(.consume)
            }

            if press.matches(PanelKeyCode.down) { return .panel(.stepPreview(by: 1)) }
            if press.matches(PanelKeyCode.up) { return .panel(.stepPreview(by: -1)) }
        }

        // 列表态：⌘F 聚焦搜索；Space 必须在 pre-dispatch 处理，insertText 到不了窗口。
        if press.matches(PanelKeyCode.f, .command) {
            return .panel(.focusSearch)
        }
        // ⇧+Return 粘贴为纯文本；普通 Return 仍走标准 action。
        if press.isPlainTextReturn {
            guard context.hasSelection else { return .panel(.consume) }
            return press.isARepeat ? .panel(.consume) : .panel(.activateSelectedItem(asPlainText: true))
        }
        if press.matches(PanelKeyCode.space) {
            guard !press.isARepeat else { return .panel(.consume) }
            return context.hasSelection ? .panel(.openPreviewForSelection) : .panel(.consume)
        }

        return .standard
    }

    private static func isTab(_ press: PanelKeyPress) -> Bool {
        press.matches(PanelKeyCode.tab)
            || press.matches(PanelKeyCode.tab, .shift)
            || press.matches(PanelKeyCode.tab, .control)
            || press.matches(PanelKeyCode.tab, [.control, .shift])
    }

    private static func focusedGroupFileIndex(_ context: PanelKeyContext) -> Int? {
        guard context.previewKind == .file, context.previewFileCount > 1 else { return nil }
        return context.focusedGroupFileIndex
    }
}
