//
//  FakeHistoryRepository.swift
//  SixOneTests
//
//  可控延迟的读口替身，用于验证不阻塞调用方与迟到结果丢弃。
//

import Foundation
@testable import SixOne

actor FakeHistoryRepository: ClipboardHistoryRepository {
    /// 查询词 → 返回的行。
    private var rowsByQuery: [String: [HistoryRow]]
    /// 查询词 → 延迟，用来制造「先发的请求后返回」。
    private var delaysByQuery: [String: Duration]
    /// 置位后所有查询都抛错。
    private var isFailing = false
    /// 依次收到的查询词。
    private(set) var requestedQueries: [String] = []
    /// 依次返回过结果的查询词。
    private(set) var returnedQueries: [String] = []
    /// 依次收到的条数上限。
    private(set) var requestedLimits: [Int] = []

    init(rowsByQuery: [String: [HistoryRow]] = [:], delaysByQuery: [String: Duration] = [:]) {
        self.rowsByQuery = rowsByQuery
        self.delaysByQuery = delaysByQuery
    }

    /// 让之后的查询都失败。
    func startFailing() {
        isFailing = true
    }

    func stopFailing() {
        isFailing = false
    }

    func latest(query: String, limit: Int) async throws -> [HistoryRow] {
        requestedQueries.append(query)
        requestedLimits.append(limit)
        if let delay = delaysByQuery[query] {
            try? await Task.sleep(for: delay)
        }
        if isFailing {
            throw FakeHistoryError.readFailed
        }
        returnedQueries.append(query)
        return Array((rowsByQuery[query] ?? []).prefix(limit))
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

    func row(id: UUID) async throws -> HistoryRow? {
        if isFailing {
            throw FakeHistoryError.readFailed
        }
        return rowsByQuery.values.flatMap { $0 }.first { $0.id == id }
    }

    func itemExists(id: UUID) async throws -> Bool {
        try await row(id: id) != nil
    }
}

/// 替身专用读失败。
enum FakeHistoryError: Error {
    case readFailed
}

extension HistoryRow {
    /// 只带标题的测试行。
    static func stub(title: String) -> HistoryRow {
        HistoryRow(
            id: UUID(),
            kind: .text,
            title: title,
            filePath: nil,
            fileCount: 0,
            contentType: nil,
            thumbnailData: nil,
            sourceAppBundleIdentifier: nil,
            lastActivityAt: Date()
        )
    }
}
