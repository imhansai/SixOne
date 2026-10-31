//
//  ClipboardContentKeyRepair.swift
//  SixOne
//
//  图片去重 key 升级后的后台重算：只处理旧版本的图片条目，分批写回。
//

import Foundation
import SwiftData
import os

actor ClipboardContentKeyRepair {
    private let container: ModelContainer
    private let logger = AppLog.logger("ContentKeyRepair")
    private static let batchSize = 50

    init(container: ModelContainer) {
        self.container = container
    }

    func runIfNeeded() async {
        let context = ModelContext(container)
        let currentVersion = ClipboardItem.currentContentKeyVersion

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
            guard let items = try? context.fetch(descriptor), !items.isEmpty else { break }

            for item in items {
                item.refreshContentKey()
            }
            do {
                try context.save()
            } catch {
                logger.error("重算图片去重 key 失败：\(error.localizedDescription, privacy: .public)")
                break
            }
            logger.notice("重算了 \(items.count, privacy: .public) 条图片条目的去重 key")
        }
    }
}
