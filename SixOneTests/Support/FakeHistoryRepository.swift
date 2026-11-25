//
//  FakeHistoryRepository.swift
//  SixOneTests
//
//  可控延迟的读口替身，用于验证不阻塞调用方与迟到结果丢弃。
//

import Foundation
@testable import SixOne

actor FakeHistoryRepository: ClipboardHistoryRepository {
    /// 查询 → 返回的行。
    private var rowsByQuery: [HistoryQuery: [HistoryRow]]
    /// 查询 → 延迟，用来制造「先发的请求后返回」。
    private var delaysByQuery: [HistoryQuery: Duration]
    /// 分组列表。
    private var collectionRows: [CollectionRow] = []
    /// 来源列表；`sourceApplications` 按传入顺序返回。
    private var sourceRows: [String] = []
    /// 条目 id → 延迟，用来制造单行刷新乱序。
    private var rowDelays: [UUID: Duration] = [:]
    /// 置位后所有查询都抛错。
    private var isFailing = false
    /// 依次收到的搜索词，兼容既有断言。
    private(set) var requestedQueries: [String] = []
    /// 依次返回过结果的搜索词。
    private(set) var returnedQueries: [String] = []
    /// 依次收到的条数上限。
    private(set) var requestedLimits: [Int] = []
    /// 依次返回过结果的条目 id。
    private(set) var returnedRowIDs: [UUID] = []
    /// `itemExists` 的调用次数，用来验证探测合并没有重复发。
    private(set) var itemExistsRequests = 0

    init(rowsByQuery: [String: [HistoryRow]] = [:], delaysByQuery: [String: Duration] = [:]) {
        self.rowsByQuery = Dictionary(uniqueKeysWithValues: rowsByQuery.map {
            (HistoryQuery(text: $0.key), $0.value)
        })
        self.delaysByQuery = Dictionary(uniqueKeysWithValues: delaysByQuery.map {
            (HistoryQuery(text: $0.key), $0.value)
        })
    }

    func setQueryDelay(_ delay: Duration, for query: String) {
        delaysByQuery[HistoryQuery(text: query)] = delay
    }

    func setRows(_ rows: [HistoryRow], for query: String) {
        rowsByQuery[HistoryQuery(text: query)] = rows
    }

    func setCollections(_ rows: [CollectionRow]) {
        collectionRows = rows
    }

    func setSourceApplications(_ rows: [String]) {
        sourceRows = rows
    }

    /// 让之后的查询都失败。
    func startFailing() {
        isFailing = true
    }

    func stopFailing() {
        isFailing = false
    }

    func latest(query: HistoryQuery, limit: Int) async throws -> [HistoryRow] {
        requestedQueries.append(query.text)
        requestedLimits.append(limit)
        if let delay = delaysByQuery[query] {
            try? await Task.sleep(for: delay)
        }
        if isFailing {
            throw FakeHistoryError.readFailed
        }
        returnedQueries.append(query.text)
        return Array((rowsByQuery[query] ?? []).prefix(limit))
    }

    func rows(after cursor: UUID, query: HistoryQuery, limit: Int) async throws -> [HistoryRow] {
        requestedQueries.append(query.text)
        requestedLimits.append(limit)
        if let delay = delaysByQuery[query] {
            try? await Task.sleep(for: delay)
        }
        if isFailing {
            throw FakeHistoryError.readFailed
        }
        returnedQueries.append(query.text)
        let all = rowsByQuery[query] ?? []
        guard let index = all.firstIndex(where: { $0.recencyID == cursor }) else { return [] }
        return Array(all[(index + 1)...].prefix(limit))
    }

    /// 等该查询返回过结果（超时返回 false），避免断言因查询未发起而恒真。
    func waitUntilReturned(_ query: String, timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if returnedQueries.contains(query) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return returnedQueries.contains(query)
    }

    /// 等至少 `count` 次查询返回过结果（超时返回 false）。
    func waitUntilReturnedCount(_ count: Int, timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if returnedQueries.count >= count { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return returnedQueries.count >= count
    }

    func setRowDelay(_ delay: Duration, for id: UUID) {
        rowDelays[id] = delay
    }

    func rowMatches(id: UUID, query: HistoryQuery) async throws -> Bool {
        if isFailing {
            throw FakeHistoryError.readFailed
        }
        return rowsByQuery[query]?.contains { $0.id == id } ?? false
    }

    func row(id: UUID) async throws -> HistoryRow? {
        if let delay = rowDelays[id] {
            try? await Task.sleep(for: delay)
        }
        if isFailing {
            throw FakeHistoryError.readFailed
        }
        let row = rowsByQuery.values.flatMap { $0 }.first { $0.id == id }
        if row != nil {
            returnedRowIDs.append(id)
        }
        return row
    }

    /// 等至少 `count` 次单行读取返回过结果（超时返回 false）。
    func waitUntilRowsReturned(_ count: Int, timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if returnedRowIDs.count >= count { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return returnedRowIDs.count >= count
    }

    func itemExists(id: UUID) async throws -> Bool {
        itemExistsRequests += 1
        return try await row(id: id) != nil
    }

    func itemExistsRequestCount() -> Int {
        itemExistsRequests
    }

    func collections() async throws -> [CollectionRow] {
        if isFailing {
            throw FakeHistoryError.readFailed
        }
        return collectionRows
    }

    func sourceApplications(limit: Int) async throws -> [String] {
        if isFailing {
            throw FakeHistoryError.readFailed
        }
        return Array(sourceRows.prefix(limit))
    }
}

/// 替身专用读失败。
enum FakeHistoryError: Error {
    case readFailed
}

extension HistoryRow {
    /// 只带标题的测试行。
    static func stub(
        title: String,
        id: UUID = UUID(),
        kind: ClipboardItemKind = .text,
        alias: String? = nil,
        sourceAppBundleIdentifier: String? = nil,
        lastActivityAt: Date = Date(),
        collectionID: UUID? = nil
    ) -> HistoryRow {
        HistoryRow(
            id: id,
            recencyID: id,
            kind: kind,
            title: title,
            alias: alias,
            filePath: nil,
            fileCount: 0,
            contentType: nil,
            thumbnailData: nil,
            thumbnailVersion: nil,
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            lastActivityAt: lastActivityAt,
            collectionID: collectionID
        )
    }
}
