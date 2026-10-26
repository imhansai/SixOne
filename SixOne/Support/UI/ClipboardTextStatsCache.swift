//
//  ClipboardTextStatsCache.swift
//  SixOne
//  文本条目的字符/词/行统计缓存，供列表与预览标题取用。

import Foundation

/// nonisolated：需在 `Task.detached` 等后台上下文计算与传递。
nonisolated struct TextStats: Equatable {
    let characters: Int
    let words: Int
    let lines: Int
}

/// 统计为 O(n)，放后台并按条目 id 缓存；主线程使用，编辑保存后调用 `invalidate(for:)`。
final class ClipboardTextStatsCache {
    private final class Box {
        let text: String
        let stats: TextStats
        init(text: String, stats: TextStats) {
            self.text = text
            self.stats = stats
        }
    }

    private let cache = NSCache<NSString, Box>()
    /// 每次失效自增；在途计算回来时代数变了就不写缓存。
    private var generations: [UUID: Int] = [:]

    init() {
        cache.countLimit = 500
    }

    func stats(for id: UUID, text: String) async -> TextStats {
        let key = id.uuidString as NSString
        if let cached = cache.object(forKey: key), cached.text == text {
            return cached.stats
        }

        let generation = generations[id, default: 0]
        let stats = await Task.detached(priority: .userInitiated) {
            TextStats.compute(from: text)
        }.value

        if generations[id, default: 0] == generation {
            cache.setObject(Box(text: text, stats: stats), forKey: key)
        }
        return stats
    }

    func invalidate(for id: UUID) {
        generations[id, default: 0] += 1
        cache.removeObject(forKey: id.uuidString as NSString)
    }
}

nonisolated extension TextStats {
    static func compute(from text: String) -> TextStats {
        var words = 0
        var lines = 1
        var inWord = false
        let whitespace = CharacterSet.whitespacesAndNewlines
        let newlines = CharacterSet.newlines
        for scalar in text.unicodeScalars {
            var isWhitespace: Bool
            if scalar.value < 0x80 {
                if (0x0A...0x0D).contains(scalar.value) { lines += 1 }
                isWhitespace = scalar == " " || (0x09...0x0D).contains(scalar.value)
            } else {
                if newlines.contains(scalar) { lines += 1 }
                // U+200B 对齐 Character.isWhitespace，按非空白处理。
                isWhitespace = scalar.value != 0x200B && whitespace.contains(scalar)
            }
            if isWhitespace {
                inWord = false
            } else if !inWord {
                inWord = true
                words += 1
            }
        }
        return TextStats(characters: text.count, words: words, lines: lines)
    }
}
