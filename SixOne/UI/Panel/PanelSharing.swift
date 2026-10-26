//
//  PanelSharing.swift
//  SixOne
//  面板分享：把条目或文件交给系统分享面板，并持有会话直到结束。

import AppKit

final class PanelSharing {
    private let manager: ClipboardManager
    private let shareState: ShareState
    private let noticeState: NoticeState
    /// 会话可能并行（AirDrop 传输时再分享），不能用一个槽位互相顶掉。
    private var sessions: Set<ShareSession> = []

    init(
        manager: ClipboardManager,
        shareState: ShareState,
        noticeState: NoticeState
    ) {
        self.manager = manager
        self.shareState = shareState
        self.noticeState = noticeState
    }

    /// 分享这一条；分享期间必须持有安全作用域访问权，否则扩展读不到文件。
    func shareRowItem(id: UUID, anchorView: NSView) {
        guard let item = manager.fetchLightItem(id: id) else { return }
        switch item.kind {
        case .file where item.fileCount > 1:
            let files = manager.startScopedShareURLs(for: item)
            guard !files.isEmpty else { return }
            present(files, relativeTo: anchorView.bounds, of: anchorView)
        case .file, .image:
            guard let file = manager.startScopedShareURL(for: item) else { return }
            present([file], relativeTo: anchorView.bounds, of: anchorView)
        case .link:
            guard let text = item.text,
                  let url = URL(string: text),
                  url.scheme != nil else { return }
            present([url], relativeTo: anchorView.bounds, of: anchorView)
        case .text, .color:
            return
        }
    }

    func sharePreviewedGroup(_ item: ClipboardItem, anchorView: NSView) {
        let files = manager.startScopedShareURLs(for: item)
        guard !files.isEmpty else {
            noticeState.showMissingFile(item.displayTitle)
            return
        }
        present(files, relativeTo: anchorView.bounds, of: anchorView)
    }

    /// 分享文件组里的单个文件。
    func sharePreviewedFile(at index: Int, of item: ClipboardItem, anchorView: NSView) {
        guard let file = manager.startScopedShareURL(for: item, fileAt: index) else {
            let name = item.allFilePaths.indices.contains(index)
                ? URL(fileURLWithPath: item.allFilePaths[index]).lastPathComponent
                : item.displayTitle
            noticeState.showMissingFile(name)
            return
        }
        present([file], relativeTo: anchorView.bounds, of: anchorView)
    }

    /// 结束仍在选服务的会话；已开始执行的服务继续持有访问权。
    func finishPickingSessions() {
        for session in sessions.filter({ $0.stage == .picking }) {
            session.finish()
        }
    }

    private func present(
        _ files: [ScopedFileURL],
        relativeTo rect: NSRect,
        of view: NSView
    ) {
        present(
            files.map(\.url),
            relativeTo: rect,
            of: view,
            scopedURLs: files.filter(\.needsStop).map(\.url)
        )
    }

    private func present(
        _ urls: [URL],
        relativeTo rect: NSRect,
        of view: NSView,
        scopedURLs: [URL] = []
    ) {
        // 同一时间只允许一个 picker。
        finishPickingSessions()
        let session = ShareSession(items: urls, scopedURLs: scopedURLs)
        session.onStageChange = { [weak self] in self?.refreshShareStage() }
        session.onFinish = { [weak self, weak session] in
            guard let self, let session else { return }
            self.sessions.remove(session)
            self.refreshShareStage()
        }
        sessions.insert(session)
        session.show(relativeTo: rect, of: view)
    }

    private func refreshShareStage() {
        if sessions.contains(where: { $0.stage == .running }) {
            shareState.stage = .running
        } else if sessions.contains(where: { $0.stage == .picking }) {
            shareState.stage = .picking
        } else {
            shareState.stage = .idle
        }
    }
}
