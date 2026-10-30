//
//  ClipboardCapturePipeline.swift
//  SixOne
//
//  剪贴板轮询与捕获流水线：隐私判定 → 快照 → 后台解析 → 串行入库。
//

import Foundation
import os

final class ClipboardCapturePipeline {
    private let pasteboard: PasteboardAccessing
    private let frontmostApplication: () -> SourceApplication?
    private let isIgnoredSource: (SourceApplication?) -> Bool
    private let writer: ClipboardHistoryWriter
    private let logger = AppLog.logger("ClipboardCapture")
    private var timer: Timer?
    private var lastChangeCount: Int
    /// 在途捕获；串行排队保证入库顺序与复制顺序一致。
    private var captureTask: Task<Void, Never>?

    init(
        pasteboard: PasteboardAccessing,
        frontmostApplication: @escaping () -> SourceApplication?,
        isIgnoredSource: @escaping (SourceApplication?) -> Bool,
        writer: ClipboardHistoryWriter,
        pollInterval: TimeInterval?
    ) {
        self.pasteboard = pasteboard
        self.frontmostApplication = frontmostApplication
        self.isIgnoredSource = isIgnoredSource
        self.writer = writer
        // 只响应启动后的新复制，避免清空历史后重启又补录残留内容。
        self.lastChangeCount = pasteboard.changeCount
        if let pollInterval {
            startMonitoring(interval: pollInterval)
        }
    }

    isolated deinit {
        timer?.invalidate()
    }

    /// 剪贴板已变化但还没被轮询认领：复制后马上唤出面板时，事件还在流水线里。
    var hasUnpolledPasteboardChange: Bool { pasteboard.changeCount != lastChangeCount }

    /// 轮询一次剪贴板；主线程只做 changeCount、隐私判定与读内容，解析交给后台。
    func pollPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        // 隐私判定须先于读内容：只看类型就拒绝，敏感字节不进内存。
        if pasteboard.isMarkedDoNotRecord {
            logger.notice("跳过被标记为不记录的剪贴板内容")
            return
        }
        let source = frontmostApplication()
        if isIgnoredSource(source) {
            return
        }
        let snapshot = pasteboard.snapshot
        guard !snapshot.items.isEmpty else { return }
        scheduleCapture(snapshot: snapshot, source: source)
    }

    /// 串行排一次捕获：等上一次落定，后台解析后再回主线程入库。
    private func scheduleCapture(snapshot: PasteboardSnapshot, source: SourceApplication?) {
        let previous = captureTask
        captureTask = Task { [weak self] in
            await previous?.value
            let prepared = await Task.detached(priority: .userInitiated) {
                PasteboardEntryParser.prepare(from: snapshot)
            }.value
            guard let self, let prepared else { return }
            self.writer.commit(prepared, source: source)
        }
    }

    func waitForPendingCapture() async {
        await captureTask?.value
    }

    /// 内部写回后同步计数，免得轮询把内部拷贝当成新复制。
    func syncLastChangeCount() {
        lastChangeCount = pasteboard.changeCount
    }

    private func startMonitoring(interval: TimeInterval) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Timer 挂在主 RunLoop 上，回调必然在主线程，直接断言隔离。
            MainActor.assumeIsolated {
                self?.pollPasteboard()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
