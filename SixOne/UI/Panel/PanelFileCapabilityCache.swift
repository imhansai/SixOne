//
//  PanelFileCapabilityCache.swift
//  SixOne
//
//  菜单校验用的文件能力缓存：只读，解析在后台，冷启动用乐观值。
//

import AppKit
import Foundation

@MainActor
final class PanelFileCapabilityCache {
    typealias Resolver = @Sendable (FileCapabilityRequest) -> FileCapabilityResolution
    typealias BookmarkWriter = (UUID, [RefreshedBookmark]) -> Void

    private struct Entry {
        let recencyID: UUID
        let capabilities: FileCapabilities
        let resolvedAt: Date
    }

    private struct RefreshKey: Hashable {
        let itemID: UUID
        let recencyID: UUID
    }

    /// 缓存有效期；文件在应用外变动后最多沿用这么久。
    static let defaultTTL: TimeInterval = 5
    private static let maxEntries = 256

    private let ttl: TimeInterval
    private let now: () -> Date
    private let resolver: Resolver
    private let onBookmarksRefreshed: BookmarkWriter
    private var entries: [UUID: Entry] = [:]
    private var tasks: [RefreshKey: Task<Void, Never>] = [:]
    private var activationObserver: NSObjectProtocol?

    init(
        ttl: TimeInterval = PanelFileCapabilityCache.defaultTTL,
        notificationCenter: NotificationCenter? = .default,
        now: @escaping () -> Date = { Date() },
        resolver: @escaping Resolver = { ClipboardFileAccess.resolveCapabilities(for: $0) },
        onBookmarksRefreshed: @escaping BookmarkWriter = { _, _ in }
    ) {
        self.ttl = ttl
        self.now = now
        self.resolver = resolver
        self.onBookmarksRefreshed = onBookmarksRefreshed
        if let notificationCenter {
            // 回到前台时文件可能已被外部改动，全部作废。
            activationObserver = notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.invalidateAll()
                }
            }
        }
    }

    isolated deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        for task in tasks.values {
            task.cancel()
        }
    }

    /// 校验入口：只读缓存；未命中或过期时后台探测，本次返回乐观值或旧值。
    func capabilities(for item: ClipboardItem, manager: ClipboardManager) -> FileCapabilities {
        capabilities(itemID: item.id, recencyID: item.recencyID) {
            Self.makeRequest(for: item, manager: manager)
        }
    }

    /// 测试与内部入口：直接给探测输入。
    func capabilities(for request: FileCapabilityRequest) -> FileCapabilities {
        capabilities(itemID: request.itemID, recencyID: request.recencyID) { request }
    }

    /// 已落定结果；测试用。乐观占位不算落定。
    func cachedCapabilities(for itemID: UUID) -> FileCapabilities? {
        guard let entry = entries[itemID], entry.resolvedAt != .distantPast else { return nil }
        return entry.capabilities
    }

    func invalidateAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        entries.removeAll()
    }

    // MARK: - 内部

    private func capabilities(
        itemID: UUID,
        recencyID: UUID,
        makeRequest: () -> FileCapabilityRequest
    ) -> FileCapabilities {
        let key = RefreshKey(itemID: itemID, recencyID: recencyID)
        if let entry = entries[itemID], entry.recencyID == recencyID {
            if now().timeIntervalSince(entry.resolvedAt) < ttl {
                return entry.capabilities
            }
            if tasks[key] == nil {
                refresh(makeRequest(), key: key)
            }
            return entry.capabilities
        }

        let request = makeRequest()
        let optimistic = Self.optimistic(for: request)
        // 先占位：结果落定前同一轮校验不重复构造请求。
        entries[itemID] = Entry(
            recencyID: recencyID,
            capabilities: optimistic,
            resolvedAt: .distantPast
        )
        refresh(request, key: key)
        return optimistic
    }

    private func refresh(_ request: FileCapabilityRequest, key: RefreshKey) {
        guard tasks[key] == nil else { return }
        let resolver = self.resolver
        let task = Task { [weak self] in
            let resolution = await Task.detached(priority: .userInitiated) {
                resolver(request)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.tasks[key] = nil
            // 探测期间条目被重新捕获：丢弃迟到结果。
            if let current = self.entries[key.itemID], current.recencyID != key.recencyID {
                return
            }
            self.entries[key.itemID] = Entry(
                recencyID: key.recencyID,
                capabilities: resolution.capabilities,
                resolvedAt: self.now()
            )
            if !resolution.refreshedBookmarks.isEmpty {
                self.onBookmarksRefreshed(key.itemID, resolution.refreshedBookmarks)
            }
            self.pruneIfNeeded()
        }
        tasks[key] = task
    }

    private func pruneIfNeeded() {
        guard entries.count > Self.maxEntries,
              let oldest = entries.min(by: { $0.value.resolvedAt < $1.value.resolvedAt })?.key
        else { return }
        entries[oldest] = nil
    }

    private static func makeRequest(
        for item: ClipboardItem,
        manager: ClipboardManager
    ) -> FileCapabilityRequest {
        FileCapabilityRequest(
            itemID: item.id,
            recencyID: item.recencyID,
            kind: item.kind,
            paths: item.allFilePaths,
            bookmark: item.securityScopeBookmark,
            bookmarks: item.securityScopeBookmarks,
            hasInlineImage: item.kind == .image && manager.hasInlineImage(id: item.id),
            hasText: item.kind == .text && manager.hasText(id: item.id),
            // 链接正文很短，按需补取；文本条目不读全文。
            isOpenableLink: item.kind == .link
                && (item.text.flatMap { URL(string: $0) }?.scheme != nil)
        )
    }

    /// 未命中时的保守结论；动作执行时会再校验。
    static func optimistic(for request: FileCapabilityRequest) -> FileCapabilities {
        switch request.kind {
        case .text:
            return FileCapabilities(canOpen: request.hasText, canReveal: false)
        case .link:
            return FileCapabilities(canOpen: request.isOpenableLink, canReveal: false)
        case .image:
            return FileCapabilities(
                canOpen: request.hasInlineImage || !request.paths.isEmpty,
                canReveal: !request.paths.isEmpty
            )
        case .file:
            return FileCapabilities(
                canOpen: !request.paths.isEmpty,
                canReveal: !request.paths.isEmpty
            )
        case .color:
            return .none
        }
    }
}
