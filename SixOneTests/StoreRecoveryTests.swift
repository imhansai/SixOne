//
//  StoreRecoveryTests.swift
//  SixOneTests
//  损坏库兜底：主库、边车文件与外部存储一起改名，新库不继承旧 blob。
//

import Foundation
import Testing
@testable import SixOne

@Suite("历史库兜底备份")
@MainActor
struct StoreRecoveryTests {
    @Test("损坏库备份时，-wal/-shm 与外部存储目录一起改名")
    func backsUpStoreSidecarsAndExternalStorage() throws {
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-store-backup")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(AppModelContainer.storeFileName)
        try Data("not a sqlite store".utf8).write(to: storeURL)
        for suffix in ["-wal", "-shm"] {
            try Data([1]).write(to: URL(fileURLWithPath: storeURL.path + suffix))
        }
        let externalData = ExternalStorageDirectory.url(forStoreAt: storeURL)
        try FileManager.default.createDirectory(at: externalData, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: externalData.appendingPathComponent("blob"))

        let backup = try #require(AppModelContainer.backupUnreadableStore(at: storeURL))

        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(!FileManager.default.fileExists(atPath: externalData.deletingLastPathComponent().path))
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let supportBackup = try #require(entries.first {
            $0.lastPathComponent.hasPrefix(".SixOne_SUPPORT.corrupt-")
        })
        #expect(FileManager.default.fileExists(
            atPath: supportBackup.appendingPathComponent("_EXTERNAL_DATA/blob").path
        ))
        for suffix in ["-wal", "-shm"] {
            #expect(FileManager.default.fileExists(atPath: backup.path + suffix))
        }
    }

    @Test("非本应用文件名拒绝备份")
    func refusesForeignStoreNames() throws {
        let directory = try TemporaryFiles.makeDirectory(prefix: "sixone-store-backup-foreign")
        defer { try? FileManager.default.removeItem(at: directory) }
        let foreign = directory.appendingPathComponent("Other.store")
        try Data([1]).write(to: foreign)

        #expect(AppModelContainer.backupUnreadableStore(at: foreign) == nil)
        #expect(FileManager.default.fileExists(atPath: foreign.path))
    }
}
