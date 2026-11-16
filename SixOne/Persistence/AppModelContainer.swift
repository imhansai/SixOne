//
//  AppModelContainer.swift
//  SixOne
//
//  历史库位置与打开策略：独立文件名；打不开则备份改名后重建，最后退回内存库。
//

import Foundation
import os
import SwiftData

enum AppModelContainer {
    private static let logger = AppLog.logger("Persistence")

    static let storeFileName = "SixOne.store"
    static let storeDirectoryName = "SixOne"

    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory
            .appending(path: storeDirectoryName, directoryHint: .isDirectory)
            .appending(path: storeFileName)
    }

    /// 打开（或创建）历史库；参数用于测试隔离。
    static func make(isStoredInMemoryOnly: Bool, storeURL: URL? = nil) -> ModelContainer {
        let schema = Schema(versionedSchema: SixOneSchemaV4.self)
        let configuration = makeConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            storeURL: storeURL
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: SixOneMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            logger.error("打开或迁移历史库失败：\(error.localizedDescription, privacy: .public)")
        }

        if !isStoredInMemoryOnly, let backup = backupUnreadableStore(at: configuration.url) {
            logger.notice("已把无法打开的历史库备份到 \(backup.lastPathComponent, privacy: .public)，改用新库")
            if let fresh = try? ModelContainer(
                for: schema,
                migrationPlan: SixOneMigrationPlan.self,
                configurations: [configuration]
            ) {
                return fresh
            }
        }

        logger.error("重建历史库仍失败，本次会话改用内存库（不落盘）")
        let memoryConfiguration = makeConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            storeURL: nil
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: SixOneMigrationPlan.self,
                configurations: [memoryConfiguration]
            )
        } catch {
            // 内存库也失败则无数据层，停在启动阶段。
            logger.fault("无法创建数据容器（含内存兜底）：\(error.localizedDescription, privacy: .public)")
            fatalError("无法创建数据容器（含内存兜底）: \(error)")
        }
    }

    private static func makeConfiguration(
        schema: Schema,
        isStoredInMemoryOnly: Bool,
        storeURL: URL?
    ) -> ModelConfiguration {
        if isStoredInMemoryOnly {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        let url = storeURL ?? defaultStoreURL
        prepareStoreDirectory(for: url)
        return ModelConfiguration(schema: schema, url: url)
    }

    /// 建库目录；失败不抛，交给 ModelContainer 报错。
    private static func prepareStoreDirectory(for url: URL) {
        let directory = url.deletingLastPathComponent()
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("创建历史库目录失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 库、边车与外部存储一起改名备份；只动本应用的文件。
    static func backupUnreadableStore(at url: URL) -> URL? {
        guard url.lastPathComponent == storeFileName else {
            logger.error("拒绝备份非本应用的库文件：\(url.lastPathComponent, privacy: .public)")
            return nil
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
        do {
            try fileManager.moveItem(at: url, to: backup)
        } catch {
            logger.error("备份历史库失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
        // -wal/-shm 一起挪，否则新库会读到旧日志。
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            if fileManager.fileExists(atPath: sidecar.path) {
                try? fileManager.moveItem(
                    at: sidecar,
                    to: URL(fileURLWithPath: backup.path + suffix)
                )
            }
        }
        // 不搬外部数据的话，新库会继承旧的孤儿 blob 并把它算进存储预算。
        if let externalBackup = backupExternalStorage(forStoreAt: url, stamp: stamp) {
            logger.notice("已把外部存储备份到 \(externalBackup.lastPathComponent, privacy: .public)")
        }
        return backup
    }

    /// 外部存储目录与库同名同目录；整体改名，避免新库继续使用旧数据。
    private static func backupExternalStorage(forStoreAt url: URL, stamp: String) -> URL? {
        // ExternalStorageDirectory 指向 .SixOne_SUPPORT/_EXTERNAL_DATA，搬整个 support 目录。
        let supportDirectory = ExternalStorageDirectory.url(forStoreAt: url)
            .deletingLastPathComponent()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: supportDirectory.path) else { return nil }
        let backup = supportDirectory.deletingLastPathComponent().appendingPathComponent(
            "\(supportDirectory.lastPathComponent).corrupt-\(stamp)",
            isDirectory: true
        )
        do {
            try fileManager.moveItem(at: supportDirectory, to: backup)
            return backup
        } catch {
            logger.error("备份外部存储失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
