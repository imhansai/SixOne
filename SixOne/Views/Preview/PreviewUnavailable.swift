//
//  PreviewUnavailable.swift
//  SixOne

import SwiftUI

/// 「无法预览此类内容」的统一占位。
struct PreviewUnavailable: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("This content cannot be previewed")
                .foregroundStyle(.secondary)
        }
    }
}
