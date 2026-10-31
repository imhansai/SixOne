//
//  ClipboardContentKeyRepair.swift
//  SixOne
//
//  图片去重 key 升级后的后台重算：只处理旧版本的图片条目，分批写回。
//

import Foundation
import SwiftData
import os

/// 去重 key 修复进度：生产落 UserDefaults，测试可注入独立实例。
nonisolated protocol ContentKeyRepairMarker: Sendable {
    func repairedVersion() -> Int?
    func markRepaired(_ version: Int)
}

/// 按库文件路径分键：换库或重建库后不会被旧标记跳过。
nonisolated struct UserDefaultsContentKeyRepairMarker: ContentKeyRepairMarker, @unchecked Sendable {
    let defaults: UserDefaults
    let key: String

    func repairedVersion() -> Int? {
        defaults.object(forKey: key) as? Int
    }

    func markRepaired(_ version: Int) {
        defaults.set(version, forKey: key)
    }
}

actor ClipboardContentKeyRepair {
    private let container: ModelContainer
    /// 健康库据此跳过整表扫描；内存库不落标记。
    private let marker: ContentKeyRepairMarker?
    private let logger = AppLog.logger("ContentKeyRepair")
    private static let batchSize = 50

    init(container: ModelContainer, marker: ContentKeyRepairMarker? = nil) {
        self.container = container
        self.marker = marker ?? Self.defaultMarker(for: container)
    }

    private static func defaultMarker(for container: ModelContainer) -> ContentKeyRepairMarker? {
        guard let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly else { return nil }
        return UserDefaultsContentKeyRepairMarker(
            defaults: .standard,
            key: "contentKeyRepairVersion:\(configuration.url.path)"
        )
    }

    func runIfNeeded() async {
        let currentVersion = ClipboardItem.currentContentKeyVersion
        if let marker, let repaired = marker.repairedVersion(), repaired >= currentVersion {
            return
        }

        let context = ModelContext(container)
        var completed = true
        while true {
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { item in
                    item.kindRaw == "image"
                        && (item.contentKeyVersion == nil || item.contentKeyVersion != currentVersion)
                }
            )
            descriptor.fetchLimit = Self.batchSize
            descriptor.propertiesToFetch = [
                \.id, \.kindRaw, \.imageData, \.contentKeySnapshot, \.contentKeyVersion,
            ]

            let items: [ClipboardItem]
            do {
                items = try context.fetch(descriptor)
            } catch {
                logger.error("重算图片去重 key 时读取失败：\(error.localizedDescription, privacy: .public)")
                completed = false
                break
            }
            guard !items.isEmpty else { break }

            for item in items {
                item.refreshContentKey()
            }
            do {
                try context.save()
            } catch {
                logger.error("重算图片去重 key 失败：\(error.localizedDescription, privacy: .public)")
                completed = false
                break
            }
            logger.notice("重算了 \(items.count, privacy: .public) 条图片条目的去重 key")
        }

        if completed {
            marker?.markRepaired(currentVersion)
        }
    }
}
