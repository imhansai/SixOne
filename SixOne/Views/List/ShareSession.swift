//
//  ShareSession.swift
//  SixOne
//

import AppKit

// MARK: - 分享会话

/// 一次分享会话：持有 picker 与 delegate，阶段/结束经回调交给 `PanelSharing`。
final class ShareSession: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    enum Stage {
        case picking
        case running
    }

    private let picker: NSSharingServicePicker
    private let access: ScopedShareAccess
    private var didFinish = false
    private(set) var stage: Stage?
    var onStageChange: (() -> Void)?
    /// 会话结束；`PanelSharing` 据此放掉唯一强引用。
    var onFinish: (() -> Void)?

    init(items: [Any], scopedURLs: [URL] = []) {
        self.picker = NSSharingServicePicker(items: items)
        self.access = ScopedShareAccess(urls: scopedURLs)
        super.init()
        picker.delegate = self
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        access.stop()
        let wasPicking = stage == .picking
        stage = nil
        if wasPicking { picker.close() }
        onStageChange?()
        onFinish?()
    }

    /// 分享面板挂在行左侧；菜单刚关闭就弹会打架，延后一拍。
    func show(relativeTo rect: NSRect, of view: NSView) {
        stage = .picking
        onStageChange?()
        DispatchQueue.main.async { [weak self] in
            self?.picker.show(relativeTo: rect, of: view, preferredEdge: .minX)
        }
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service == nil {
            finish()
        } else {
            stage = .running
            onStageChange?()
        }
    }

    func sharingServicePicker(
        _ picker: NSSharingServicePicker,
        delegateFor service: NSSharingService
    ) -> NSSharingServiceDelegate? {
        self
    }

    func sharingService(_ service: NSSharingService, didShareItems items: [Any]) {
        finish()
    }

    func sharingService(_ service: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        finish()
    }
}

/// 一次分享持有的安全作用域访问权；`stop()` 幂等，deinit 兜底。
private nonisolated final class ScopedShareAccess {
    private var urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
    }

    func stop() {
        let pending = urls
        urls = []
        for url in pending {
            url.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        stop()
    }
}
