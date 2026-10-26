//
//  PDFPreview.swift
//  SixOne

import PDFKit
import SwiftUI

/// PDF 预览：PDFKit 的 PDFView，文本选择与 Cmd+C/A 比 Quick Look 可靠。
struct PDFPreview: NSViewRepresentable {
    let url: URL

    @Environment(PanelContext.self) private var panelContext

    func makeNSView(context: Context) -> PDFView {
        let view = PanelPDFView()
        view.onCopyFallback = { panelContext.actions?.panelDidRequestCopyItem() }
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.pageShadowsEnabled = false
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        (view as? PanelPDFView)?.onCopyFallback = {
            panelContext.actions?.panelDidRequestCopyItem()
        }
        guard view.document?.documentURL != url else { return }
        view.document = PDFDocument(url: url)
    }
}
