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

    /// ⇧+Return / ⇧+Enter：粘贴为纯文本。
    var isPlainTextReturn: Bool {
        modifiers == [.shift]
            && (keyCode == PanelKeyCode.returnKey || keyCode == PanelKeyCode.keypadEnter)
    }

    /// ⌘+1…9 / ⌘⇧+1…9 对应的可见行偏移（0 起）；其它组合为 nil。
    var quickPasteOffset: Int? {
        guard !isARepeat else { return nil }
        guard modifiers == [.command] || modifiers == [.command, .shift] else { return nil }
        switch keyCode {
        case PanelKeyCode.one: return 0
        case PanelKeyCode.two: return 1
        case PanelKeyCode.three: return 2
        case PanelKeyCode.four: return 3
        case PanelKeyCode.five: return 4
        case PanelKeyCode.six: return 5
        case PanelKeyCode.seven: return 6
        case PanelKeyCode.eight: return 7
        case PanelKeyCode.nine: return 8
        default: return nil
        }
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

    case activateSelectedItem(asPlainText: Bool)
    case activateFocusedGroupFile(index: Int)
    /// 粘贴当前完整可见区的第 offset 行（0 起）。
    case pasteVisibleRow(offset: Int, asPlainText: Bool)
    /// 粘贴组内可见区的第 offset 个文件。
    case pasteVisibleGroupFile(offset: Int, asPlainText: Bool)

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
    /// 完整可见行数；⌘+数字只在这段范围内生效。
    var visibleRowCount = 0

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

    /// 预览停在文件组列表。
    var isGroupOverview: Bool {
        previewKind == .file && previewFileCount > 1 && !isViewingGroupFile
    }

    /// 列表可快速粘贴；预览仅文件组总览。
    var canQuickPasteVisibleRow: Bool {
        !isEditing && !isMoreActionsFocused && (!isPreviewing || isGroupOverview)
    }
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
    static let one = UInt16(kVK_ANSI_1)
    static let two = UInt16(kVK_ANSI_2)
    static let three = UInt16(kVK_ANSI_3)
    static let four = UInt16(kVK_ANSI_4)
    static let five = UInt16(kVK_ANSI_5)
    static let six = UInt16(kVK_ANSI_6)
    static let seven = UInt16(kVK_ANSI_7)
    static let eight = UInt16(kVK_ANSI_8)
    static let nine = UInt16(kVK_ANSI_9)
}
