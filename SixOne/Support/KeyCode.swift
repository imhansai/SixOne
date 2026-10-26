//
//  KeyCode.swift
//  SixOne

/// Carbon 事件修饰键掩码，与 `RegisterEventHotKey` 一致。
enum ModifierMasks {
    static let cmd: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12
}
