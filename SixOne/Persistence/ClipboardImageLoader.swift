//
//  ClipboardImageLoader.swift
//  SixOne
//
//  预览用图片数据读取：后台 context 按 id 取，避免主线程加载大字段。
//

import Foundation
import SwiftData

actor ClipboardImageLoader {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func imageData(id: UUID) -> Data? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.id, \.imageData]
        guard let item = try? context.fetch(descriptor).first else { return nil }
        return item.imageData
    }
}
