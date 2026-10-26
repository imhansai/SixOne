//
//  SourceApplication.swift
//  SixOne
//

import AppKit

/// 复制来源：bundle id 用于隐私忽略，名称用于角标；值类型便于测试。
nonisolated struct SourceApplication: Equatable {
    let bundleIdentifier: String?
    let name: String?

    init(bundleIdentifier: String?, name: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }

    init(_ application: NSRunningApplication) {
        self.init(bundleIdentifier: application.bundleIdentifier, name: application.localizedName)
    }
}
