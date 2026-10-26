//
//  OrderedUUID.swift
//  SixOne

import Foundation

/// 时间有序 UUIDv7：毫秒前缀加同毫秒序号保持单调；只在主线程使用，故不加锁。
enum OrderedUUID {
    private static var lastMillis: UInt64 = 0
    private static var sequence: UInt16 = 0

    static func make() -> UUID {
        let now = currentMillis()
        var millis: UInt64
        if now > lastMillis {
            lastMillis = now
            sequence = UInt16.random(in: 0...0x0FFF)
            millis = now
        } else if now == lastMillis {
            let next = sequence + 1
            if next > 0x0FFF {
                // 序号耗尽：推进到下一毫秒以保持单调。
                lastMillis += 1
                sequence = UInt16.random(in: 0...0x0FFF)
                millis = lastMillis
            } else {
                sequence = next
                millis = lastMillis
            }
        } else {
            // 时钟回拨：沿用上次时间戳递增，避免新 id 变小。
            lastMillis += 1
            sequence = (sequence + 1) & 0x0FFF
            millis = lastMillis
        }

        var bytes = UUID().uuid
        bytes.0 = UInt8((millis >> 40) & 0xFF)
        bytes.1 = UInt8((millis >> 32) & 0xFF)
        bytes.2 = UInt8((millis >> 24) & 0xFF)
        bytes.3 = UInt8((millis >> 16) & 0xFF)
        bytes.4 = UInt8((millis >> 8) & 0xFF)
        bytes.5 = UInt8(millis & 0xFF)
        bytes.6 = 0x70 | UInt8((sequence >> 8) & 0x0F)
        bytes.7 = UInt8(sequence & 0xFF)
        bytes.8 = 0x80 | (bytes.8 & 0x3F)
        return UUID(uuid: bytes)
    }

    private static func currentMillis() -> UInt64 {
        let seconds = max(0, Date().timeIntervalSince1970)
        return UInt64((seconds * 1000).rounded(.down))
    }
}
