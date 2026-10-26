//
//  SystemSymbolicHotKey.swift
//  SixOne
//
//  系统 symbolic hotkey 的只读快照，仅用于全局快捷键注册前的冲突预检。
//

import Carbon.HIToolbox
import Foundation

struct SystemSymbolicHotKey: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let isEnabled: Bool

    /// 当前系统定义的 symbolic hotkey；读不到时返回空数组。
    static func current() -> [SystemSymbolicHotKey] {
        // out 参数是未托管引用，按 Create 规则由调用方释放。
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr,
              let array,
              let entries = array.takeRetainedValue() as? [NSDictionary] else {
            return []
        }
        return entries.compactMap { entry in
            guard let keyCode = entry[kHISymbolicHotKeyCode] as? NSNumber,
                  let modifiers = entry[kHISymbolicHotKeyModifiers] as? NSNumber else {
                return nil
            }
            let enabled = (entry[kHISymbolicHotKeyEnabled] as? NSNumber)?.boolValue ?? true
            return SystemSymbolicHotKey(
                keyCode: keyCode.uint32Value,
                modifiers: modifiers.uint32Value,
                isEnabled: enabled
            )
        }
    }
}
