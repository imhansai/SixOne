//
//  PreviewStateTests.swift
//  SixOneTests

import Testing
@testable import SixOne

@Suite("预览编辑状态")
struct PreviewStateTests {
    @Test("开始编辑清掉上一次的落盘标记")
    func startEditingClearsCommitFlag() {
        let state = PreviewState()
        state.startEditing()
        state.finishEditing()
        #expect(state.shouldCommitEditing)

        state.hasUnsavedChanges = true
        state.startEditing()

        #expect(state.isEditing)
        #expect(!state.shouldCommitEditing)
        #expect(!state.hasUnsavedChanges)
    }

    @Test("完成编辑：退出编辑态并标记落盘")
    func finishEditingCommits() {
        let state = PreviewState()
        state.startEditing()
        state.hasUnsavedChanges = true

        state.finishEditing()

        #expect(!state.isEditing)
        #expect(state.shouldCommitEditing)
        #expect(!state.hasUnsavedChanges)
    }

    @Test("取消编辑：退出编辑态但不落盘")
    func cancelEditingDoesNotCommit() {
        let state = PreviewState()
        state.startEditing()
        state.hasUnsavedChanges = true

        state.cancelEditing()

        #expect(!state.isEditing)
        #expect(!state.shouldCommitEditing)
        #expect(!state.hasUnsavedChanges)
    }

    @Test("关闭预览：清掉编辑会话与落盘标记")
    func closeResetsEditing() {
        let state = PreviewState()
        state.startEditing()
        state.hasUnsavedChanges = true

        state.close()

        #expect(!state.isEditing)
        #expect(!state.shouldCommitEditing)
        #expect(!state.hasUnsavedChanges)
    }

    @Test("关闭预览：清掉组列表可见范围与复制反馈")
    func closeResetsGroupListState() {
        let state = PreviewState()
        state.groupVisibleRowRange = 0...3
        state.markGroupFileCopied(at: 2)

        state.close()

        #expect(state.groupVisibleRowRange == nil)
        #expect(state.groupCopyFeedbackIndex == nil)
    }

    @Test("组内文件复制反馈按代际推进，同一文件重复复制也能再闪")
    func groupCopyFeedbackAdvances() {
        let state = PreviewState()
        state.markGroupFileCopied(at: 2)
        #expect(state.groupCopyFeedbackIndex == 2)
        let revision = state.groupCopyFeedbackRevision

        state.markGroupFileCopied(at: 2)
        #expect(state.groupCopyFeedbackRevision == revision + 1)
    }

    @Test("⌘S 请求：只在编辑态递增，且不退出编辑")
    func requestSaveOnlyWhileEditing() {
        let state = PreviewState()
        state.requestSave()
        #expect(state.saveRequestID == 0)

        state.startEditing()
        state.requestSave()
        #expect(state.saveRequestID == 1)
        #expect(state.isEditing)

        state.cancelEditing()
        state.requestSave()
        #expect(state.saveRequestID == 1)
    }
}
