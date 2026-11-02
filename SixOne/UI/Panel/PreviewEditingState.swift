//
//  PreviewEditingState.swift
//  SixOne
//
//  预览编辑会话：编辑态、落盘标记与保存请求。
//

import Foundation
import Observation

@Observable
final class PreviewEditingState {
    var isEditing = false
    /// 退出编辑时是否落盘；只有「完成」置位。`reset()` 也会把 isEditing 置 false，需要这个区分。
    var shouldCommitEditing = false
    var hasUnsavedChanges = false
    private(set) var saveRequestID = 0

    func start() {
        shouldCommitEditing = false
        hasUnsavedChanges = false
        isEditing = true
    }

    /// 「完成」：标记落盘再退出；已不在编辑态时不再改标记，避免重复调用翻成取消。
    func finish() {
        guard isEditing else { return }
        shouldCommitEditing = true
        hasUnsavedChanges = false
        isEditing = false
    }

    /// ⌘S：请求保存但保持编辑态。
    func requestSave() {
        guard isEditing else { return }
        saveRequestID += 1
    }

    /// 取消编辑：退出但不落盘，正文恢复为进入编辑前的快照。
    func cancel() {
        guard isEditing else { return }
        shouldCommitEditing = false
        hasUnsavedChanges = false
        isEditing = false
    }

    func reset() {
        shouldCommitEditing = false
        hasUnsavedChanges = false
        isEditing = false
    }
}
