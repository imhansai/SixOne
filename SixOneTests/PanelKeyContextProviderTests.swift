//
//  PanelKeyContextProviderTests.swift
//  SixOneTests

import AppKit
import Testing
@testable import SixOne

@Suite("按键现场：模态让路")
@MainActor
struct PanelKeyContextProviderTests {
    @Test("确认弹窗：清空历史与删除单条都算模态")
    func confirmationCountsAsModal() {
        let confirmation = ConfirmationState()
        #expect(!PanelKeyContextProvider.isModalPresented(confirmation: confirmation, attachedSheet: nil))

        confirmation.isClearingHistory = true
        #expect(PanelKeyContextProvider.isModalPresented(confirmation: confirmation, attachedSheet: nil))

        confirmation.reset()
        confirmation.pendingDeletionID = UUID()
        #expect(PanelKeyContextProvider.isModalPresented(confirmation: confirmation, attachedSheet: nil))

        confirmation.reset()
        confirmation.isDiscardingPreviewEdit = true
        #expect(PanelKeyContextProvider.isModalPresented(confirmation: confirmation, attachedSheet: nil))

        confirmation.reset()
        #expect(!confirmation.isPresenting)
    }

    @Test("普通 sheet：没有确认状态也照样算模态")
    func attachedSheetCountsAsModal() {
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        #expect(PanelKeyContextProvider.isModalPresented(
            confirmation: ConfirmationState(),
            attachedSheet: sheet
        ))
    }
}
