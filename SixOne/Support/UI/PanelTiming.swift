//
//  PanelTiming.swift
//  SixOne
//  面板短暂反馈的停留时长，集中定义避免漂移。

import Foundation

enum PanelTiming {
    static let notice: TimeInterval = 2.5
    static let copiedFeedback: TimeInterval = 1.2
    static let colorCopiedNotice: TimeInterval = 1.4
    /// 组内文件位置浮层的停留时长。
    static let groupPositionHint: TimeInterval = 1.6
}
