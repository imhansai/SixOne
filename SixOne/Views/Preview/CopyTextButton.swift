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
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            guard !text.isEmpty else { return }
            onCopy(text)
            didCopy = true
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .seconds(PanelTiming.copiedFeedback))
                guard !Task.isCancelled else { return }
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
        .accessibilityValue(text)
        .onChange(of: text) { _, _ in
            resetTask?.cancel()
            didCopy = false
        }
        .onDisappear {
            resetTask?.cancel()
        }
    }
}
