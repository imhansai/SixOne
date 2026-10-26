//
//  InMemorySettingsStorage.swift
//  SixOneTests
//

@testable import SixOne

/// 内存设置：不碰用户真实偏好。
@MainActor
final class InMemorySettingsStorage: SettingsStorage {
    private var values: [String: Any]
    /// 写入次数，用于断言省写行为。
    private(set) var setCount = 0

    init(_ values: [String: Any] = [:]) {
        self.values = values
    }

    func object(forKey key: String) -> Any? {
        values[key]
    }

    func set(_ value: Any?, forKey key: String) {
        setCount += 1
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }
}
