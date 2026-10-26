//
//  AppLog.swift
//  SixOne
//  统一日志入口；固定子系统字符串，测试宿主也不会落错子系统，nonisolated 便于 actor 取用。

import os

nonisolated enum AppLog {
    private static let subsystem = "dev.sixone.SixOne"

    static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
