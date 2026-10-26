//
//  PanelFocusPolicy.swift
//  SixOne
//  「焦点变化后面板该不该收起」的纯函数判定。

/// 一次判定所需的现场事实。
nonisolated struct PanelFocusSnapshot: Equatable {
    var isSharing = false
    var hasAttachedSheet = false
    /// 用户正按着菜单栏状态项；开关由鼠标抬起负责，这一拍不能收。
    var isPressingStatusItem = false
    var isAppFrontmost = false
    var isPanelKeyWindow = false
    var isTextAuxiliaryPanelKey = false
    var hasApplicationSheet = false
    var isEditingText = false
    var clickedOutside = false
    /// 前台是别的进程的系统辅助面板（自动填充、指纹认证等）。
    var isSystemHelperFrontmost = false
    var hasKeyWindow = true
}

nonisolated enum PanelFocusPolicy {
    /// 「点击面板外」或「失去 key」都不等于焦点真正离开；规则按序匹配，顺序即行为。
    static func shouldHide(_ snapshot: PanelFocusSnapshot) -> Bool {
        if snapshot.isSharing { return false }
        if snapshot.hasAttachedSheet { return false }
        if snapshot.isPressingStatusItem { return false }
        if snapshot.isAppFrontmost, snapshot.isPanelKeyWindow { return false }
        if snapshot.isTextAuxiliaryPanelKey { return false }
        if snapshot.hasApplicationSheet { return false }
        // 编辑中系统辅助进程（自动填充、Touch ID）抢前台不算切走；用户主动点外面才算。
        if snapshot.isEditingText, !snapshot.clickedOutside, snapshot.isSystemHelperFrontmost {
            return false
        }
        if !snapshot.isAppFrontmost { return true }
        // key 正在切换（辅助面板刚抢过焦点）时先保留。
        if !snapshot.hasKeyWindow { return false }
        return true
    }
}
