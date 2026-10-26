//
//  TemporaryFiles.swift
//  SixOneTests
//
//  临时目录里的真实文件；清理由调用方负责。
//

import Foundation

enum TemporaryFiles {
    /// 临时目录里新建一个带前缀的空目录。
    static func makeDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 临时目录里的一个文件，内容为 UTF-8 文本。
    @discardableResult
    static func makeFile(prefix: String, contents: String) throws -> URL {
        try makeFile(prefix: prefix, data: Data(contents.utf8))
    }

    /// 临时目录里的一个文件。
    @discardableResult
    static func makeFile(prefix: String, data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).txt")
        try data.write(to: url)
        return url
    }

    /// 一个目录里的 N 个真实文件，返回目录与各文件路径（顺序与文件编号一致）。
    static func makeFiles(count: Int, prefix: String) throws -> (directory: URL, paths: [String]) {
        let directory = try makeDirectory(prefix: prefix)
        let paths = try (0..<count).map { index -> String in
            let url = directory.appendingPathComponent("文件\(index).txt")
            try Data("x".utf8).write(to: url)
            return url.path
        }
        return (directory, paths)
    }
}
