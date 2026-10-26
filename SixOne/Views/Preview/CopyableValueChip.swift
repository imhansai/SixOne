//
//  CopyableValueChip.swift
//  SixOne
//
//  预览里「点一下就复制」的值胶囊；复制反馈由调用方负责。
//

import SwiftUI

struct CopyableValueChip: View {
    /// 前置标签；整体值传 nil。
    let label: String?
    let value: String
    var emphasized = false
    var labelWidth: CGFloat?
    let onCopy: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 5) {
                if let label {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(width: labelWidth, alignment: .leading)
                }
                Text(value)
                    .font(.system(
                        size: emphasized ? 15 : 12,
                        weight: emphasized ? .medium : .regular,
                        design: .monospaced
                    ))
                    .foregroundStyle(emphasized ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.primary.opacity(isHovering ? 0.14 : 0.06))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointerStyle(.link)
        .appTooltip(Localizer.string("Copy"))
    }
}
