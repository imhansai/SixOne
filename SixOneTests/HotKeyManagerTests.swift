//
//  HotKeyManagerTests.swift
//  SixOneTests
//  快捷键状态机：成功 / 被占用 / 改键失败回滚；用假注册口，不碰真实快捷键。

import AppKit
import Carbon.HIToolbox
import Testing
@testable import SixOne

@Suite("全局快捷键注册")
@MainActor
struct HotKeyManagerTests {
    private func makeManager(
        registrar: FakeHotKeyRegistrar,
        monitor: FakeHotKeyEventMonitor = FakeHotKeyEventMonitor(),
        storage: SettingsStorage = InMemorySettingsStorage()
    ) -> HotKeyManager {
        HotKeyManager(
            onTrigger: {},
            registrar: registrar,
            eventMonitor: monitor,
            storage: storage,
            systemHotKeys: { [] }
        )
    }

    @Test("启动注册成功：可用")
    func reapplySucceeds() {
        let registrar = FakeHotKeyRegistrar()
        let manager = makeManager(registrar: registrar)

        manager.reapply()

        #expect(manager.isConfigured)
        #expect(manager.isRegistered)
        #expect(manager.isActive)
    }

    @Test("启动注册失败：如实留在未注册态")
    func reapplyFailureStaysUnregistered() {
        let registrar = FakeHotKeyRegistrar()
        let manager = makeManager(registrar: registrar)
        registrar.isOccupied = { _, _ in true }

        manager.reapply()

        #expect(manager.isConfigured)
        #expect(!manager.isRegistered)
        #expect(!manager.isActive)
    }

    @Test("已经注册时重复 reapply 不重复注册")
    func reapplyIsIdempotent() {
        let registrar = FakeHotKeyRegistrar()
        let manager = makeManager(registrar: registrar)
        manager.reapply()

        manager.reapply()

        #expect(registrar.registered.count == 1)
    }

    @Test("改键失败：返回 false、回滚到原组合，并把原来的注册装回去")
    func updateRollsBackOnFailure() {
        let registrar = FakeHotKeyRegistrar()
        let manager = makeManager(registrar: registrar)
        manager.reapply()
        let original = manager.displayString
        registrar.isOccupied = { keyCode, modifiers in
            keyCode == UInt32(kVK_ANSI_Y)
                && modifiers == (ModifierMasks.cmd | ModifierMasks.option)
        }

        #expect(!manager.update(keyCode: UInt16(kVK_ANSI_Y), modifiers: [.command, .option]))

        #expect(manager.displayString == original)
        #expect(manager.isRegistered)
        #expect(manager.isActive)
    }

    @Test("改键成功：新组合生效并落盘，下一次启动按它恢复")
    func updatePersists() {
        let registrar = FakeHotKeyRegistrar()
        let storage = InMemorySettingsStorage()
        let manager = makeManager(registrar: registrar, storage: storage)

        #expect(manager.update(keyCode: UInt16(kVK_ANSI_Y), modifiers: [.command, .option]))

        let restored = makeManager(registrar: registrar, storage: storage)
        #expect(restored.displayString == manager.displayString)
        #expect(restored.isConfigured)
        #expect(!restored.isRegistered) // 新实例尚未注册，由 reapply() 负责
    }

    @Test("清除快捷键：不是失败，只是停用")
    func clearingIsNotAFailure() {
        let registrar = FakeHotKeyRegistrar()
        let manager = makeManager(registrar: registrar)
        manager.reapply()

        manager.clear()

        #expect(!manager.isConfigured)
        #expect(!manager.isActive)
        #expect(registrar.releaseCount == 1)
        manager.reapply()
        #expect(registrar.registered.count == 1)
    }

    @Test("按键事件按实例分发：两个实例不会互相顶掉")
    func routesTriggersPerInstance() throws {
        let registrar = FakeHotKeyRegistrar()
        let monitor = FakeHotKeyEventMonitor()
        var firstCount = 0
        var secondCount = 0
        let first = HotKeyManager(
            onTrigger: { firstCount += 1 },
            registrar: registrar,
            eventMonitor: monitor,
            storage: InMemorySettingsStorage()
        )
        let second = HotKeyManager(
            onTrigger: { secondCount += 1 },
            registrar: registrar,
            eventMonitor: monitor,
            storage: InMemorySettingsStorage()
        )
        first.reapply()
        second.reapply()
        try #require(monitor.triggers.count == 2, "每个实例都该装自己的按键处理器")

        monitor.triggers[0]()

        #expect(firstCount == 1)
        #expect(secondCount == 0, "第一个实例的事件被转给了第二个")

        monitor.triggers[1]()

        #expect(secondCount == 1)
    }

    @Test("实例释放时卸载按键处理器，不留进程级残留")
    func releasesEventHandlerOnDeinit() {
        let monitor = FakeHotKeyEventMonitor()
        var manager: HotKeyManager? = HotKeyManager(
            onTrigger: {},
            registrar: FakeHotKeyRegistrar(),
            eventMonitor: monitor,
            storage: InMemorySettingsStorage()
        )
        manager?.reapply()
        #expect(monitor.released.isEmpty)

        manager = nil

        #expect(monitor.released == [0])
    }

    @Test("处理器装不上：快捷键仍算注册成功，下次注册再兜一次")
    func survivesEventHandlerInstallFailure() {
        let registrar = FakeHotKeyRegistrar()
        let monitor = FakeHotKeyEventMonitor()
        monitor.failsToInstall = true
        let manager = makeManager(registrar: registrar, monitor: monitor)

        manager.reapply()

        #expect(manager.isRegistered)
        #expect(manager.isActive)
        #expect(monitor.triggers.isEmpty)

        monitor.failsToInstall = false
        #expect(manager.restoreDefaults())

        #expect(monitor.triggers.count == 1)
    }

    @Test("配置变化通知每个订阅者都收到")
    func notifiesEveryChangeObserver() {
        let registrar = FakeHotKeyRegistrar()
        let manager = makeManager(registrar: registrar)
        var first = 0
        var second = 0
        manager.observeChanges { first += 1 }
        manager.observeChanges { second += 1 }

        #expect(manager.update(keyCode: UInt16(kVK_ANSI_Y), modifiers: [.command, .option]))
        manager.clear()

        #expect(first == 2)
        #expect(second == 2)
    }

    @Test("键名：数字、标点、功能键与导航键都要显示得出来，不是只认字母")
    func displaysNonLetterKeys() {
        let cmd = ModifierMasks.cmd
        // 注入固定键名，不依赖测试机键盘布局。
        let name: (UInt32) -> String = { code in
            switch code {
            case UInt32(kVK_ANSI_1): "1"
            case UInt32(kVK_ANSI_Comma): ","
            case UInt32(kVK_F1): "F1"
            case UInt32(kVK_Home): "↖"
            case UInt32(kVK_Space): "Space"
            case UInt32(kVK_ANSI_V): "V"
            default: "Key"
            }
        }

        #expect(HotKeyManager.displayString(
            keyCode: UInt32(kVK_ANSI_1), modifiers: cmd, keyName: name
        ) == "⌘1")
        #expect(HotKeyManager.displayString(
            keyCode: UInt32(kVK_ANSI_Comma), modifiers: cmd, keyName: name
        ) == "⌘,")
        #expect(HotKeyManager.displayString(
            keyCode: UInt32(kVK_F1), modifiers: cmd, keyName: name
        ) == "⌘F1")
        #expect(HotKeyManager.displayString(
            keyCode: UInt32(kVK_Home), modifiers: cmd, keyName: name
        ) == "⌘↖")
        #expect(HotKeyManager.displayString(
            keyCode: UInt32(kVK_Space), modifiers: cmd, keyName: name
        ) == "⌘Space")
        // 修饰键按 ⌃⌥⇧⌘ 排，与系统菜单一致。
        #expect(
            HotKeyManager.displayString(
                keyCode: UInt32(kVK_ANSI_V),
                modifiers: ModifierMasks.control | ModifierMasks.cmd,
                keyName: name
            ) == "⌃⌘V"
        )
    }

    @Test("只按 Command 的组合被拒绝，不碰注册口")
    func rejectsCommandOnly() {
        let registrar = FakeHotKeyRegistrar()
        let manager = makeManager(registrar: registrar)

        #expect(!manager.update(keyCode: UInt16(kVK_ANSI_Y), modifiers: [.command]))
        #expect(registrar.registered.isEmpty)
    }

    @Test("命中系统 symbolic hotkey 时拒绝注册")
    func rejectsSystemReserved() {
        let registrar = FakeHotKeyRegistrar()
        let reserved = SystemSymbolicHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: ModifierMasks.cmd | ModifierMasks.control,
            isEnabled: true
        )
        let manager = HotKeyManager(
            onTrigger: {},
            registrar: registrar,
            eventMonitor: FakeHotKeyEventMonitor(),
            storage: InMemorySettingsStorage(),
            systemHotKeys: { [reserved] }
        )

        #expect(!manager.update(keyCode: UInt16(kVK_Space), modifiers: [.command, .control]))
        #expect(registrar.registered.isEmpty)
    }

    @Test("启动时旧配置不满足规则：不注册")
    func reapplyRejectsLegacyCommandOnly() {
        let storage = InMemorySettingsStorage()
        storage.set(true, forKey: "globalHotKeyConfigured")
        storage.set(Int(kVK_ANSI_Y), forKey: "globalHotKeyCode")
        storage.set(Int(ModifierMasks.cmd), forKey: "globalHotKeyModifiers")
        let registrar = FakeHotKeyRegistrar()
        let manager = HotKeyManager(
            onTrigger: {},
            registrar: registrar,
            eventMonitor: FakeHotKeyEventMonitor(),
            storage: storage,
            systemHotKeys: { [] }
        )

        manager.reapply()

        #expect(!manager.isRegistered)
        #expect(!manager.isActive)
        #expect(registrar.registered.isEmpty)
    }

    @Test("菜单快捷键：特殊键与修饰键按系统菜单格式给出")
    func menuKeyEquivalentUsesSystemFormat() throws {
        let registrar = FakeHotKeyRegistrar()
        let manager = makeManager(registrar: registrar)

        #expect(manager.update(keyCode: UInt16(kVK_F1), modifiers: [.command, .control]))

        let equivalent = try #require(manager.menuKeyEquivalent)
        #expect(equivalent.key == String(UnicodeScalar(NSF1FunctionKey)!))
        #expect(equivalent.modifiers == [.command, .control])

        // 小键盘无法用单个 key equivalent 表达，退回标题后缀。
        #expect(manager.update(keyCode: UInt16(kVK_ANSI_Keypad1), modifiers: [.command, .control]))
        #expect(manager.menuKeyEquivalent == nil)
    }
}
