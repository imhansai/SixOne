//
//  FakeHotKey.swift
//  SixOneTests
//  全局快捷键的假注册口与假事件监视器，不碰真实快捷键。
//

import Carbon.HIToolbox
@testable import SixOne

@MainActor
final class FakeHotKeyRegistrar: HotKeyRegistering {
    var isOccupied: (_ keyCode: UInt32, _ modifiers: UInt32) -> Bool = { _, _ in false }
    private(set) var registered: [(keyCode: UInt32, modifiers: UInt32)] = []
    private(set) var releaseCount = 0

    func register(keyCode: UInt32, modifiers: UInt32) -> (handle: HotKeyRegistration?, status: OSStatus) {
        registered.append((keyCode, modifiers))
        guard !isOccupied(keyCode, modifiers) else {
            return (nil, OSStatus(-9868)) // eventHotKeyExistsErr
        }
        return (HotKeyRegistration { [weak self] in self?.releaseCount += 1 }, noErr)
    }
}

@MainActor
final class FakeHotKeyEventMonitor: HotKeyEventMonitoring {
    private(set) var triggers: [() -> Void] = []
    private(set) var released: [Int] = []
    var failsToInstall = false

    func install(trigger: @escaping () -> Void) -> (
        registration: HotKeyEventMonitorRegistration?,
        status: OSStatus
    ) {
        guard !failsToInstall else { return (nil, OSStatus(-1)) }
        let index = triggers.count
        triggers.append(trigger)
        return (
            HotKeyEventMonitorRegistration { [weak self] in self?.released.append(index) },
            noErr
        )
    }
}
