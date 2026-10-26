//
//  FilePreviewKind.swift
//  SixOne

import Foundation
import UniformTypeIdentifiers

/// 预览方式：按文件类型判定一次，不读内容；内容判断留给各渲染器。
enum FilePreviewKind {
    case image
    case html
    case pdf
    case text
    case quickLook

    static func of(_ url: URL) -> FilePreviewKind {
        let type = UTType(filenameExtension: url.pathExtension)

        // 影片统一交给 Quick Look：MKV/AVI/WebM 等容器只有它能放。
        if isMovie(url) { return .quickLook }

        if let type {
            // GIF 排在图片前：内置图片预览只画第一帧，Quick Look 才会播放。
            if type.conforms(to: .gif) { return .quickLook }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .html) { return .html }
            if type.conforms(to: .pdf) { return .pdf }
            // 富文本按纯文本展示会是一堆控制字，交给系统渲染。
            if type.conforms(to: .rtf) || type.conforms(to: .rtfd) { return .quickLook }
            if type.conforms(to: .text) { return .text }
        }
        // 类型判不出（无扩展名、自定义后缀）时按文本试，读不出再回退。
        if type == nil || type?.isDynamic == true { return .text }
        return .quickLook
    }

    /// 是否影片：只看类型与扩展名；面板收起时据此停掉可能出声的预览。
    static func isMovie(_ url: URL) -> Bool {
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .movie) {
            return true
        }
        return movieFileExtensions.contains(url.pathExtension.lowercased())
    }

    private static let movieFileExtensions: Set<String> = [
        "mp4", "m4v", "mov", "avi", "mkv", "webm", "flv", "wmv",
        "mpg", "mpeg", "ts", "3gp", "3g2",
    ]
}
