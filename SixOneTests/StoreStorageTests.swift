//
//  StoreStorageTests.swift
//  SixOneTests
//  真实文件库验证大字段落在库外（`.externalStorage` 确实生效）。

import Foundation
import Testing
@testable import SixOne

@Suite("历史库存储")
@MainActor
struct StoreStorageTests {
    @Test("大位图落在库文件之外（externalStorage 真的生效）")
    func largeBitmapIsStoredOutsideTheDatabase() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }

        let container = AppModelContainer.make(isStoredInMemoryOnly: false, storeURL: fixture.storeURL)
        let context = container.mainContext
        let item = ClipboardItem(kind: .image, imageData: Data(repeating: 0xA5, count: 4 * 1024 * 1024))
        context.insert(item)
        try context.save()

        #expect(fixture.hasExternalDataFiles, "预期库旁边出现 _EXTERNAL_DATA 目录")
        let storeSize = try fixture.storeSizeInBytes
        #expect(storeSize < 1024 * 1024, "主库文件不该装下 4MB 位图，实际 \(storeSize) 字节")
    }
}

@MainActor
private struct StoreFixture {
    let directory: URL
    let storeURL: URL

    init() throws {
        directory = try TemporaryFiles.makeDirectory(prefix: "sixone-store")
        storeURL = directory.appendingPathComponent(AppModelContainer.storeFileName)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    var storeSizeInBytes: Int64 {
        get throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }
    }

    /// 是否出现外部存储目录（Core Data 存放 `.externalStorage` 数据）。
    var hasExternalDataFiles: Bool {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.path.contains("_EXTERNAL_DATA") { return true }
        }
        return false
    }
}

@Suite("历史库位置与兜底")
@MainActor
struct StoreLocationTests {
    @Test("默认库位置是应用专属的目录 + 文件名，不是共享的 default.store")
    func defaultStoreIsNamespaced() {
        let url = AppModelContainer.defaultStoreURL
        #expect(url.lastPathComponent == AppModelContainer.storeFileName)
        #expect(url.lastPathComponent != "default.store")
        #expect(url.deletingLastPathComponent().lastPathComponent == AppModelContainer.storeDirectoryName)
    }

    @Test("打不开的库被改名备份，并原地建出新库")
    func unreadableOwnStoreIsBackedUp() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        try Data("not a database".utf8).write(to: fixture.storeURL)

        let container = AppModelContainer.make(isStoredInMemoryOnly: false, storeURL: fixture.storeURL)
        #expect(FileManager.default.fileExists(atPath: fixture.storeURL.path))
        let backups = try fixture.corruptBackupNames
        #expect(backups.count == 1, "预期恰好一份备份，实际 \(backups)")
        #expect(backups.first?.hasPrefix("\(AppModelContainer.storeFileName).corrupt-") == true)
        let context = container.mainContext
        context.insert(ClipboardItem(kind: .text, text: "after recovery"))
        try context.save()
    }

    @Test("别人的库文件绝不改名（共享文件名不能碰）")
    func foreignStoreFileIsLeftAlone() throws {
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-foreign")
        defer { try? FileManager.default.removeItem(at: directory) }
        let foreign = directory.appendingPathComponent("default.store")
        let original = Data("not a database either".utf8)
        try original.write(to: foreign)

        _ = AppModelContainer.make(isStoredInMemoryOnly: false, storeURL: foreign)

        #expect(try Data(contentsOf: foreign) == original)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(!names.contains { $0.contains(".corrupt-") }, "不该动别人的文件，实际目录内容 \(names)")
    }
}

private extension StoreFixture {
    var corruptBackupNames: [String] {
        get throws {
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.contains(".corrupt-") && !$0.hasSuffix("-wal") && !$0.hasSuffix("-shm") }
        }
    }
}
