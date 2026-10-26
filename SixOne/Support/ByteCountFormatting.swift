//
//  ByteCountFormatting.swift
//  SixOne

import Foundation

enum ByteCountFormatting {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func string(fromByteCount count: Int64) -> String {
        formatter.string(fromByteCount: count)
    }
}
