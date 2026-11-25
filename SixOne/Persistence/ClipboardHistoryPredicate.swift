//
//  ClipboardHistoryPredicate.swift
//  SixOne
//
//  历史查询谓词：仓库取窗与菜单名次统计共用一份命中口径。
//

import Foundation
import SwiftData

nonisolated enum ClipboardHistoryPredicate {
    /// 每个维度单独成谓词再合取；单条表达式过长会拖垮类型检查，也方便独立测试。
    static func make(
        query: HistoryQuery,
        newerThan: UUID? = nil,
        olderThan: UUID? = nil
    ) -> Predicate<ClipboardItem>? {
        let text = query.text
        let filter = query.filter
        var predicates: [Predicate<ClipboardItem>] = []

        if let olderThan {
            predicates.append(#Predicate { $0.recencyID < olderThan })
        }
        if let newerThan {
            predicates.append(#Predicate { $0.recencyID > newerThan })
        }
        if !filter.collections.isEmpty {
            let collectionPredicates = filter.collections
                .sorted { $0.uuidString < $1.uuidString }
                .map { collectionID in
                    #Predicate<ClipboardItem> { $0.collectionID == collectionID }
                }
            predicates.append(Predicate(any: collectionPredicates))
        }
        if !text.isEmpty {
            predicates.append(#Predicate { item in
                (item.searchText?.localizedStandardContains(text) ?? false)
                    || (item.titleSnapshot?.localizedStandardContains(text) ?? false)
                    || (item.alias?.localizedStandardContains(text) ?? false)
                    || (item.filePathsSearchText?.localizedStandardContains(text) ?? false)
            })
        }
        if !filter.kinds.isEmpty {
            let kinds = filter.kinds.map(\.rawValue).sorted()
            predicates.append(#Predicate { kinds.contains($0.kindRaw) })
        }
        if !filter.sourceApps.isEmpty {
            // CoreData 不支持对可空列做 IN / nil 合并；逐来源等值再取并集。
            let sourcePredicates = filter.sourceApps.sorted().map { source in
                #Predicate<ClipboardItem> { $0.sourceAppBundleIdentifier == source }
            }
            predicates.append(Predicate(any: sourcePredicates))
        }
        if !filter.dateRanges.isEmpty {
            let datePredicates = filter.dateRanges.map { range -> Predicate<ClipboardItem> in
                let bounds = range.bounds()
                let start = bounds.start
                let end = bounds.end
                return #Predicate { $0.lastActivityAt >= start && $0.lastActivityAt < end }
            }
            predicates.append(Predicate(any: datePredicates))
        }

        guard !predicates.isEmpty else { return nil }
        return Predicate(all: predicates)
    }
}
