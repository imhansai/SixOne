//
//  Wait.swift
//  SixOneTests
//
//  测试等待原语：有可观察条件时轮询，`settle` 仅用于无条件的断言。
//

@MainActor
enum Wait {
    /// 轮询等条件成立；超时返回最后一次判定结果。
    @discardableResult
    static func until(
        timeout: Duration = .seconds(5),
        interval: Duration = .milliseconds(20),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: interval)
        }
        return condition()
    }

    /// 等一段固定时间。用在没有可观察条件的断言前（例如「不该发生的变化没发生」）。
    static func settle(milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}
