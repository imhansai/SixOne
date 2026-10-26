//
//  OrderedUUIDTests.swift
//  SixOneTests

import Foundation
import Testing
@testable import SixOne

@Suite("时间有序 UUID")
struct OrderedUUIDTests {
    @Test("连续生成的 id 严格递增（含同一毫秒内的连发）")
    func generationIsMonotonic() {
        var previous = OrderedUUID.make()
        var outOfOrder = 0
        for _ in 0..<50_000 {
            let next = OrderedUUID.make()
            if next <= previous { outOfOrder += 1 }
            previous = next
        }
        #expect(outOfOrder == 0)
    }

    @Test("id 不重复")
    func idsAreUnique() {
        let ids = Set((0..<5_000).map { _ in OrderedUUID.make() })
        #expect(ids.count == 5_000)
    }

    @Test("版本位是 7、变体位是 10xx")
    func versionAndVariantBits() {
        var allSamplesConform = true
        for _ in 0..<200 {
            let bytes = OrderedUUID.make().uuid
            if bytes.6 >> 4 != 0x7 || bytes.8 & 0xC0 != 0x80 {
                allSamplesConform = false
                break
            }
        }
        #expect(allSamplesConform)
    }
}
