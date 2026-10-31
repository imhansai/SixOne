//
//  PreviewSupport.swift
//  SixOne
//
//  预览共用的小组件与 URL 展示名。
//

import AppKit
import SwiftUI

struct GroupFilePositionBadge: View {
    let position: Int
    let total: Int

    var body: some View {
        Text("\(position) / \(total)")
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            .allowsHitTesting(false)
    }
}

extension URL {
    /// 应用包路径的显示名（去掉 .app 后缀）。
    var displayName: String {
        var name = lastPathComponent
        if name.hasSuffix(".app") {
            name.removeLast(4)
        }
        return name
    }
}
