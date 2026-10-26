//
//  SettingsStorage.swift
//  SixOne

import Foundation

/// 设置持久化口；生产实现是 `UserDefaults`，测试用内存实现。
protocol SettingsStorage: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStorage {}
