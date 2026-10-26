//
//  HotKeyEventMonitor.swift
//  SixOne
//
//  全局按键事件的安装口；抽成协议便于测试断言安装与分发。
//

import Carbon.HIToolbox

struct HotKeyEventMonitorRegistration {
    let release: () -> Void
}

@MainActor
protocol HotKeyEventMonitoring {
    /// 安装按键处理器；registration 为 nil 表示失败，status 为系统状态码。
    func install(trigger: @escaping () -> Void) -> (
        registration: HotKeyEventMonitorRegistration?,
        status: OSStatus
    )
}

/// 生产实现：Carbon `InstallEventHandler`；闭包经 `userData` 找回本次安装，多个实例不会互顶。
final class CarbonHotKeyEventMonitor: HotKeyEventMonitoring {
    private final class Box {
        let trigger: () -> Void

        init(_ trigger: @escaping () -> Void) {
            self.trigger = trigger
        }
    }

    func install(trigger: @escaping () -> Void) -> (
        registration: HotKeyEventMonitorRegistration?,
        status: OSStatus
    ) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passRetained(Box(trigger)).toOpaque()
        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let box = Unmanaged<Box>.fromOpaque(userData).takeUnretainedValue()
                // 处理器在主线程跑；再跳一拍主队列，避免在事件分发中直接做面板动作。
                DispatchQueue.main.async { box.trigger() }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &ref
        )
        guard status == noErr, let ref else {
            // 安装失败要释放盒子，避免泄漏。
            Unmanaged<Box>.fromOpaque(pointer).release()
            return (nil, status)
        }
        return (
            HotKeyEventMonitorRegistration {
                RemoveEventHandler(ref)
                Unmanaged<Box>.fromOpaque(pointer).release()
            },
            status
        )
    }
}
