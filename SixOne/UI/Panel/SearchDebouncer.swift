//
//  SearchDebouncer.swift
//  SixOne
//  交付防抖：delay 内的重复调用只保留最后一次。

import Foundation

final class SearchDebouncer {
    /// 够盖住连续击键，又不至于让人觉得卡。
    static let defaultDelay: TimeInterval = 0.2

    private let delay: TimeInterval
    private var work: DispatchWorkItem?

    init(delay: TimeInterval = SearchDebouncer.defaultDelay) {
        self.delay = delay
    }

    /// `cancel()` 不保证闭包不被调用，闭包仍须自己认出已过期。
    func schedule(_ action: @escaping () -> Void) {
        cancel()
        let item = DispatchWorkItem(block: action)
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        work?.cancel()
        work = nil
    }
}
