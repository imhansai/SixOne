//
//  CopyTextButton.swift
//  SixOne
//
//  行内拷贝按钮，点击后图标短暂变为对勾。
//

import SwiftUI

struct CopyTextButton: View {
    let text: String
    let help: String
    let onCopy: (String) -> Void

    @State private var didCopy = false
    @State private var isHovering = false
    @State private var feedback = TransientFeedback()

    var body: some View {
        Button {
            guard !text.isEmpty else { return }
            onCopy(text)
            didCopy = true
            feedback.schedule(after: PanelTiming.copiedFeedback) {
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(didCopy ? Color.green : (isHovering ? Color.primary : Color.secondary))
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(Color.primary.opacity(isHovering && !didCopy ? 0.10 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointerStyle(.link)
        .appTooltip(didCopy ? Localizer.string("Copied") : help)
        .accessibilityLabel(help)
        // 长文本只把开头交给辅助功能，避免整段复制。
        .accessibilityValue(text.count > 200 ? String(text.prefix(200)) + "…" : text)
        .onChange(of: text) { _, _ in
            feedback.cancel()
            didCopy = false
        }
        .onDisappear {
            feedback.cancel()
        }
    }
}
