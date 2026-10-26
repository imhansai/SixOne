//
//  LocalizationCoverageTests.swift
//  SixOneTests
//  字面量键须都在 `Localizable.xcstrings`；读不到仓库（沙盒）时跳过整个套件。

import Foundation
import Testing

@Suite("本地化键覆盖", .enabled(if: LocalizationCoverage.isAvailable))
struct LocalizationCoverageTests {
    @Test("Localizer.string 用到的每个字面量键都在目录里")
    func everyLiteralKeyExistsInCatalog() throws {
        let catalogKeys = try LocalizationCoverage.catalogKeys()
        let usedKeys = try LocalizationCoverage.literalKeysInSources()

        // 扫描失效时不能因「没有键」而通过。
        #expect(!usedKeys.isEmpty, "一个 Localizer.string 调用都没扫到，扫描逻辑可能已经失效")

        let missing = usedKeys.subtracting(catalogKeys).sorted()
        #expect(
            missing.isEmpty,
            "这些键在代码里用了、Localizable.xcstrings 里没有：\(missing)"
        )
    }

    @Test("目录里的 zh-Hans 覆盖：除专有名词与纯格式键外都应有译文")
    func chineseCoverageIsComplete() throws {
        // 产品名、仓库地址与纯格式化串无需翻译。
        let exempt: Set<String> = [
            "SixOne",
            "GitHub",
            "https://github.com/imhansai/SixOne",
            "%lld",
            "%lld / %lld",
        ]
        let missing = try LocalizationCoverage.keysMissingChinese().subtracting(exempt).sorted()
        #expect(missing.isEmpty, "这些键缺少 zh-Hans 译文：\(missing)")
    }
}

/// 只读源码与目录的小工具；`nonisolated` 供 `@Sendable` 条件求值。
nonisolated enum LocalizationCoverage {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var catalogURL: URL {
        repoRoot.appending(path: "SixOne/Localizable.xcstrings")
    }

    static var sourcesDirectory: URL {
        repoRoot.appending(path: "SixOne", directoryHint: .isDirectory)
    }

    static var isAvailable: Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        return fileManager.isReadableFile(atPath: catalogURL.path)
            && fileManager.fileExists(atPath: sourcesDirectory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.isReadableFile(atPath: sourcesDirectory.path)
    }

    // MARK: - 目录

    private static func catalog() throws -> [String: Any] {
        let data = try Data(contentsOf: catalogURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return root["strings"] as? [String: Any] ?? [:]
    }

    static func catalogKeys() throws -> Set<String> {
        Set(try catalog().keys)
    }

    static func keysMissingChinese() throws -> Set<String> {
        var missing: Set<String> = []
        for (key, value) in try catalog() {
            let entry = value as? [String: Any]
            let localizations = entry?["localizations"] as? [String: Any]
            let unit = (localizations?["zh-Hans"] as? [String: Any])?["stringUnit"] as? [String: Any]
            let translated = (unit?["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if translated?.isEmpty != false {
                missing.insert(key)
            }
        }
        return missing
    }

    // MARK: - 源码扫描

    static func literalKeysInSources() throws -> Set<String> {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourcesDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        var keys: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            keys.formUnion(literalKeys(in: source))
        }
        return keys
    }

    static func literalKeys(in source: String) -> Set<String> {
        let marker = "Localizer.string("
        var keys: Set<String> = []
        var searchStart = source.startIndex

        while let markerRange = source.range(of: marker, range: searchStart..<source.endIndex) {
            var index = markerRange.upperBound
            var depth = 1
            var inString = false
            var literal = ""

            while index < source.endIndex, depth > 0 {
                let character = source[index]
                if inString {
                    if character == "\\" {
                        index = source.index(after: index)
                        if index < source.endIndex {
                            literal.append(source[index] == "n" ? "\n" : source[index])
                        }
                    } else if character == "\"" {
                        inString = false
                        keys.insert(literal)
                        literal = ""
                    } else {
                        literal.append(character)
                    }
                } else if character == "\"" {
                    inString = true
                } else if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                }
                index = source.index(after: index)
            }
            searchStart = markerRange.upperBound
        }
        return keys
    }
}
