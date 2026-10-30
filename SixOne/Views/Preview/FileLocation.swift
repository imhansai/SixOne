//
//  FileLocation.swift
//  SixOne
//
//  文件位置：文件名 + 绝对路径。
//

import Foundation

nonisolated struct FileLocation: Equatable, Sendable {
    let name: String
    /// 归一化后的绝对路径。
    let path: String

    init?(path: String?) {
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        guard !name.isEmpty else { return nil }
        self.name = name
        self.path = url.path
    }

    init?(url: URL?) {
        self.init(path: url?.path)
    }

    static func make(
        paths: [String],
        scopedFileURL: URL?,
        groupURLs: [URL?],
        groupFileIndex: Int?
    ) -> FileLocation? {
        // 多文件组：总览不显示，查看某项时用解析后的当前路径。
        if paths.count > 1 {
            guard let index = groupFileIndex, paths.indices.contains(index) else { return nil }
            if groupURLs.indices.contains(index), let url = groupURLs[index] {
                return FileLocation(url: url)
            }
            return FileLocation(path: paths[index])
        }

        if let scopedFileURL {
            return FileLocation(url: scopedFileURL)
        }
        return paths.first.flatMap { FileLocation(path: $0) }
    }
}
