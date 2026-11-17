//
//  PanelTiming.swift
//  SixOne
//  面板短暂反馈的时长与动画，集中定义避免漂移。

import Foundation
import SwiftUI

enum PanelTiming {
    static let notice: TimeInterval = 2.5
    static let copiedFeedback: TimeInterval = 1.2
    static let colorCopiedNotice: TimeInterval = 1.4
    /// 组内文件位置浮层的停留时长。
    static let groupPositionHint: TimeInterval = 1.6
}

enum PanelAnimation {
    /// 行内复制反馈（勾选/高亮）的弹性切换。
    static let copyFeedback = Animation.spring(response: 0.3, dampingFraction: 0.7)
}
