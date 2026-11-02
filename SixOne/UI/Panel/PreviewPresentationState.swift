//
//  PreviewPresentationState.swift
//  SixOne
//
//  预览呈现状态：当前条目、格式开关与安全作用域 URL。
//

import Foundation
import Observation

@Observable
final class PreviewPresentationState {
    var item: ClipboardItem?
    /// 是否按原始格式显示；每次呈现预览都经 `reset()` 复位，默认从纯文本开始。
    var showsFormatting = false
    /// bookmark 解析并 start 后的 URL；预览关闭时统一停止访问。
    var scopedFileURL: ScopedFileURL?
    var scopedGroupURLs: [ScopedFileURL?] = []

    func reset() {
        scopedFileURL?.stopAccessIfNeeded()
        scopedFileURL = nil
        for url in scopedGroupURLs { url?.stopAccessIfNeeded() }
        scopedGroupURLs = []
        item = nil
        showsFormatting = false
    }
}
