//
//  ScrollerFlashProbe.swift
//  SixOneTests
//
//  统计 `flashScrollers()` 调用次数，验证程序化滚动确实点亮了系统滚动条。
//

import AppKit
import ObjectiveC.runtime

/// 按滚动视图实例统计 `flashScrollers()` 调用次数。
@MainActor
enum ScrollerFlashProbe {
    nonisolated(unsafe) private static var counts: [ObjectIdentifier: Int] = [:]
    /// 使用者计数；最后一个离开的负责还原。
    nonisolated(unsafe) private static var users = 0
    /// 改写前的原实现；非 nil 表示生效中。
    nonisolated(unsafe) private static var originalImplementation: IMP?

    /// 安装探针（可重入，与 `uninstall()` 配对）。
    static func install() {
        users += 1
        guard originalImplementation == nil else { return }
        let selector = #selector(NSScrollView.flashScrollers)
        guard let method = class_getInstanceMethod(NSScrollView.self, selector) else { return }
        let original = method_getImplementation(method)
        originalImplementation = original
        let block: @convention(block) (AnyObject) -> Void = { object in
            counts[ObjectIdentifier(object), default: 0] += 1
            typealias Fn = @convention(c) (AnyObject, Selector) -> Void
            unsafeBitCast(original, to: Fn.self)(object, selector)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// 卸载探针；最后一个使用者离开时清空计数并还原。
    static func uninstall() {
        guard users > 0 else { return }
        users -= 1
        guard users == 0 else { return }
        counts.removeAll()
        guard let original = originalImplementation else { return }
        originalImplementation = nil
        let selector = #selector(NSScrollView.flashScrollers)
        guard let method = class_getInstanceMethod(NSScrollView.self, selector) else { return }
        method_setImplementation(method, original)
    }

    static func count(for scrollView: NSScrollView) -> Int {
        counts[ObjectIdentifier(scrollView), default: 0]
    }
}
