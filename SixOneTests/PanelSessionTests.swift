//
//  PanelSessionTests.swift
//  SixOneTests

import Foundation
import Testing
@testable import SixOne

/// 面板恢复：挂起期间条目可能被裁剪，须剔除已不存在的选中与锚点。
@Suite("面板会话恢复")
struct PanelSessionTests {
    @Test("停在顶部附近要重载最近一窗，滚到深处不重载")
    func deepScrollDecision() {
        #expect(!session(topVisibleIndex: 0).isDeepScroll)
        #expect(session(topVisibleIndex: ClipboardLayout.viewportRowCount).isDeepScroll == false)
        #expect(session(topVisibleIndex: ClipboardLayout.viewportRowCount + 1).isDeepScroll)
        #expect(session(topVisibleIndex: 40).isDeepScroll)
    }

    @Test("选中项还在窗口内时原样恢复")
    func restoresWindowSelection() {
        let selected = UUID()
        let other = UUID()
        let resolution = session(selected: selected, isActive: true)
            .resolve(againstRows: [row(other), row(selected)])

        #expect(resolution.selectedItemID == selected)
        #expect(resolution.isSelectionActive)
    }

    @Test("选中项已被裁剪时回落为「没有选中」")
    func dropsTrimmedSelection() {
        let resolution = session(selected: UUID(), isActive: true)
            .resolve(againstRows: [row(UUID())])

        #expect(resolution.selectedItemID == nil)
        #expect(!resolution.isSelectionActive)
    }

    @Test("锚点行还在时给出它的行号")
    func resolvesScrollAnchor() {
        let first = UUID()
        let anchor = UUID()
        let resolution = session(anchor: anchor)
            .resolve(againstRows: [row(first), row(anchor)])

        #expect(resolution.scrollToRowID == anchor)
    }

    @Test("锚点行已被裁剪时不发滚动请求")
    func dropsTrimmedAnchor() {
        let resolution = session(anchor: UUID())
            .resolve(againstRows: [row(UUID())])

        #expect(resolution.scrollToRowID == nil)
    }

    @Test("空会话什么都不恢复")
    func emptySession() {
        let resolution = session(isActive: true).resolve(againstRows: [row(UUID())])

        #expect(resolution.selectedItemID == nil)
        #expect(!resolution.isSelectionActive)
        #expect(resolution.scrollToRowID == nil)
    }

    private func session(
        selected: UUID? = nil,
        anchor: UUID? = nil,
        topVisibleIndex: Int = 0,
        isActive: Bool = false
    ) -> PanelSession {
        PanelSession(
            previewItemID: nil,
            selectedItemID: selected,
            topVisibleRowID: anchor,
            topVisibleIndex: topVisibleIndex,
            isSelectionActive: isActive
        )
    }

    private func row(_ id: UUID) -> HistoryRow {
        HistoryRow(
            id: id,
            kind: .text,
            title: "行",
            filePath: nil,
            fileCount: 0,
            contentType: nil,
            thumbnailData: nil,
            sourceAppBundleIdentifier: nil,
            lastActivityAt: Date()
        )
    }
}
