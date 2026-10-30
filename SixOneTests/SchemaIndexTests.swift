//
//  SchemaIndexTests.swift
//  SixOneTests
//  索引不只在新库生效：V2 库迁移到 V3 后也必须真的有 id 索引。
//

import Foundation
import SQLite3
import SwiftData
import Testing
@testable import SixOne

@Suite("历史库索引")
@MainActor
struct SchemaIndexTests {
    @Test("新建 V3 库包含 id 索引")
    func freshStoreHasIDIndex() throws {
        let fixture = try IndexFixture()
        defer { fixture.cleanUp() }

        let container = AppModelContainer.make(
            isStoredInMemoryOnly: false,
            storeURL: fixture.storeURL
        )
        let item = ClipboardItem(kind: .text, text: "index")
        container.mainContext.insert(item)
        try container.mainContext.save()

        #expect(try fixture.hasIndex(onColumn: "ZID"), "新建库没有 id 索引")
    }

    @Test("V2 库迁移到 V3 后包含 id 索引")
    func migratedStoreHasIDIndex() throws {
        let fixture = try IndexFixture()
        defer { fixture.cleanUp() }

        do {
            let schema = Schema(versionedSchema: SixOneSchemaV2.self)
            let configuration = ModelConfiguration(schema: schema, url: fixture.storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let item = SixOneSchemaV2.ClipboardItem(kind: .text, text: "legacy")
            item.refreshTitleSnapshot()
            item.refreshContentKey()
            container.mainContext.insert(item)
            try container.mainContext.save()
        }

        let container = AppModelContainer.make(
            isStoredInMemoryOnly: false,
            storeURL: fixture.storeURL
        )
        _ = container.mainContext

        #expect(try fixture.hasIndex(onColumn: "ZID"), "迁移后的库没有 id 索引")
    }
}

@MainActor
private struct IndexFixture {
    let directory: URL
    let storeURL: URL

    init() throws {
        directory = try TemporaryFiles.makeDirectory(prefix: "sixone-index")
        storeURL = directory.appendingPathComponent(AppModelContainer.storeFileName)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    func hasIndex(onColumn column: String) throws -> Bool {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { return false }
        defer { sqlite3_close(database) }

        var list: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA index_list('ZCLIPBOARDITEM')",
            -1,
            &list,
            nil
        ) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(list) }

        while sqlite3_step(list) == SQLITE_ROW {
            guard let rawName = sqlite3_column_text(list, 1) else { continue }
            let name = String(cString: rawName)
            if indexContains(database: database, index: name, column: column) {
                return true
            }
        }
        return false
    }

    private func indexContains(
        database: OpaquePointer,
        index: String,
        column: String
    ) -> Bool {
        var info: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA index_info('\(index)')",
            -1,
            &info,
            nil
        ) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(info) }

        while sqlite3_step(info) == SQLITE_ROW {
            guard let rawColumn = sqlite3_column_text(info, 2) else { continue }
            if String(cString: rawColumn) == column { return true }
        }
        return false
    }
}
