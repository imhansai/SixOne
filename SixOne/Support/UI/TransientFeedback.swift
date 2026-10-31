//
//  TransientFeedback.swift
//  SixOne
//  短暂反馈的计时器：新调度取消旧调度，视图离开时统一收尾。
//

import Foundation

/// 只管“过一会儿执行一次”；状态与动画仍留在各自视图里。
@MainActor
final class TransientFeedback {
    private var task: Task<Void, Never>?

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    isolated deinit {
        task?.cancel()
    }
}
