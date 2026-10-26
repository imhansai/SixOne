//
//  PanelKeyTypes.swift
//  SixOne
//  面板键盘的值类型：按键、动作、现场与键码。

import AppKit
import Carbon.HIToolbox

struct PanelKeyPress: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    /// 按键重复：开关类动作要忽略，方向键要保留。
    let isARepeat: Bool

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], isARepeat: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .shift, .option, .control])
        self.isARepeat = isARepeat
    }

    init(_ event: NSEvent) {
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags, isARepeat: event.isARepeat)
    }

    func matches(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }

    var isTextFindingCommand: Bool {
        matches(PanelKeyCode.f, .command)
            || matches(PanelKeyCode.g, .command)
            || matches(PanelKeyCode.g, [.command, .shift])
            || matches(PanelKeyCode.e, .command)
            || matches(PanelKeyCode.a, [.command, .option])
    }

    /// 查找栏聚焦时可执行的查找动作；⌥⌘F / ⌥⌘A 刻意留给 NSTextFinder。
    var previewFindCommand: NSTextFinder.Action? {
        if matches(PanelKeyCode.f, .command) { return .showFindInterface }
        if matches(PanelKeyCode.g, .command) { return .nextMatch }
        if matches(PanelKeyCode.g, [.command, .shift]) { return .previousMatch }
        if matches(PanelKeyCode.e, .command) { return .setSearchString }
        return nil
    }
}

enum PanelKeyAction: Equatable {
    case consume

    // 窗口级
    case hidePanel
    case cycleFocus(backwards: Bool)

    case focusSearch

    case escape
    case cancelEditing
    case dismissPreviewFindBar
    case performPreviewFindCommand(NSTextFinder.Action)
    case openPreviewForSelection
    case closePreview

    case activateSelectedItem
    case activateFocusedGroupFile(index: Int)

    // 移动
    case stepPreview(by: Int)
    case jumpPreview(to: Int)
    case jumpPreviewToOldest
    case moveGroupSelection(by: Int)
    case jumpGroupSelection(toFirst: Bool)
    case stepGroupFile(by: Int)
    case jumpGroupFile(toFirst: Bool)
    case showGroupFile(index: Int)
    case showGroupOverview
    case focusGroupFilter
    case focusGroupList
}

// MARK: - 现场状态

/// 解释一次按键所需的现场状态；字段全有默认值，测试只写关心的那几个。
struct PanelKeyContext {
    var previewKind: ClipboardItemKind?
    var previewFileCount = 0
    var isViewingGroupFile = false
    /// 当前聚焦的组内文件下标（单文件态是正在看的，列表态是选中的）。
    var focusedGroupFileIndex: Int?
    /// 这一方向还有行可去；移动本身由执行侧做。
    var canMoveGroupSelectionUp = false
    var canMoveGroupSelectionDown = false
    var isGroupFilterFocused = false

    var hasSelection = false

    var isSearchFocused = false
    var isMoreActionsFocused = false

    var isModalPresented = false

    var isEditing = false
    var isPreviewFindBarVisible = false
    /// 面板是否为 key；字体/颜色等辅助面板抢 key 时要区别对待。
    var isPanelKeyWindow = true
    /// 第一响应者是否有输入法组合标记。
    var isIMEComposing = false

    var isPreviewTextFocused = false
    /// 文本视图里选中了文字；⌘C 应复制选区而非整条。
    var hasPreviewTextSelection = false

    var isPreviewing: Bool { previewKind != nil }
}

// MARK: - 键码

/// 面板用到的键码集中一处。
enum PanelKeyCode {
    static let tab = UInt16(kVK_Tab)
    static let escape = UInt16(kVK_Escape)
    static let space = UInt16(kVK_Space)
    static let delete = UInt16(kVK_Delete)
    static let returnKey = UInt16(kVK_Return)
    static let keypadEnter = UInt16(kVK_ANSI_KeypadEnter)
    static let up = UInt16(kVK_UpArrow)
    static let down = UInt16(kVK_DownArrow)
    static let left = UInt16(kVK_LeftArrow)
    static let right = UInt16(kVK_RightArrow)
    static let a = UInt16(kVK_ANSI_A)
    static let c = UInt16(kVK_ANSI_C)
    static let e = UInt16(kVK_ANSI_E)
    static let f = UInt16(kVK_ANSI_F)
    static let g = UInt16(kVK_ANSI_G)
}
