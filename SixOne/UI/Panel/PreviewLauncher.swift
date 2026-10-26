//
//  PreviewLauncher.swift
//  SixOne

import Foundation
import os

/// 打开预览：校验目标，并把安全作用域访问权交给 `PreviewState` 持有。
struct PreviewLauncher {
    let manager: ClipboardManager
    let previewState: PreviewState
    let noticeState: NoticeState

    private let logger = AppLog.logger("Preview")

    /// 打开/替换预览；校验失败时保持当前预览并返回 false。
    @discardableResult
    func present(_ item: ClipboardItem) -> Bool {
        guard let plan = plan(for: item) else { return false }
        previewState.close()
        previewState.scopedFileURL = plan.scopedFileURL
        previewState.scopedGroupURLs = plan.scopedGroupURLs
        previewState.item = item
        return true
    }

    @discardableResult
    func presentIfPossible(id: UUID) -> Bool {
        guard previewState.item?.id != id, let item = manager.fetchFullItem(id: id) else { return false }
        if item.kind == .file, item.fileCount > 1 {
            noticeState.showGroupPreviewRequiresList()
            return false
        }
        return present(item)
    }

    // MARK: - 校验

    private struct Plan {
        let scopedFileURL: ScopedFileURL?
        var scopedGroupURLs: [ScopedFileURL?] = []
    }

    /// 校验条目是否可预览；失败时已弹提示并返回 nil。
    private func plan(for item: ClipboardItem) -> Plan? {
        // 图片靠位图预览，源文件只用于标题/路径；解析不到 bookmark 也不拦。
        if item.kind == .image {
            return Plan(scopedFileURL: resolvedScopedURL(for: item))
        }
        guard item.kind == .file else { return Plan(scopedFileURL: nil) }

        // 个别文件失联不拦预览，全部失联才拒绝。
        if item.fileCount > 1 {
            let scopedURLs = manager.scopedFileURLs(for: item)
            guard scopedURLs.contains(where: { $0 != nil }) else {
                logger.warning("打开预览前检查：文件组内 \(item.fileCount) 个文件全部不可用")
                noticeState.showMissingFile(item.displayTitle)
                return nil
            }
            return Plan(scopedFileURL: nil, scopedGroupURLs: scopedURLs)
        }

        // bookmark 能跟踪重命名或移入废纸篓，解析成功就允许预览。
        if let scoped = resolvedScopedURL(for: item) {
            return Plan(scopedFileURL: scoped)
        }

        if let path = item.filePath {
            guard FileManager.default.fileExists(atPath: path) else {
                logger.warning("打开预览前检查：文件不存在，拒绝预览 \(path)")
                noticeState.showMissingFile(URL(fileURLWithPath: path).lastPathComponent)
                return nil
            }
            guard FileManager.default.isReadableFile(atPath: path) else {
                logger.warning("打开预览前检查：文件无访问权限，拒绝预览 \(path)")
                noticeState.showInaccessibleFile(URL(fileURLWithPath: path).lastPathComponent)
                return nil
            }
        }
        return Plan(scopedFileURL: nil)
    }

    private func resolvedScopedURL(for item: ClipboardItem) -> ScopedFileURL? {
        guard let bookmark = item.securityScopeBookmark,
              let url = SecurityScopedFileAccess.startAccess(bookmark: bookmark) else { return nil }
        return ScopedFileURL(url: url, needsStop: true)
    }
}
