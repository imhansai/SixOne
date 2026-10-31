//
//  ClipboardHistoryEventBusTests.swift
//  SixOneTests
//  事件总线退订：token 移除后不再收到事件。
//

import Testing
@testable import SixOne

@Suite("历史事件总线")
@MainActor
struct ClipboardHistoryEventBusTests {
    @Test("退订后不再收到事件")
    func unsubscribeStopsDelivery() {
        let bus = ClipboardHistoryEventBus()
        var seen = 0
        let token = bus.observe { _ in seen += 1 }

        bus.post(.trimmed)
        bus.removeObserver(token)
        bus.post(.trimmed)

        #expect(seen == 1)
    }
}
