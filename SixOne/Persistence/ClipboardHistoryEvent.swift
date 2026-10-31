//
//  ClipboardHistoryEvent.swift
//  SixOne
//
//  历史库 → 界面的事件通道：强类型事件 + 显式总线，测试可各持一条互不干扰。
//

import Foundation

enum ClipboardHistoryEvent: Equatable {
    case inserted(id: UUID)
    /// 条目被触达，置顶；`isExternal` 表示这次触达来自外部应用的新复制（去重命中）。
    case touched(id: UUID, isExternal: Bool = false)
    /// 缩略图生成完成，原位刷新不改顺序。
    case thumbnailUpdated(id: UUID)
    case deleted(id: UUID)
    /// 批量裁剪，列表可能仍有剩余。
    case trimmed
    case cleared
}

/// 事件总线：写方 `post`、读方 `observe`；全程主线程，可按 token 退订。
@MainActor
final class ClipboardHistoryEventBus {
    typealias Observation = UUID

    private var handlers: [Observation: (ClipboardHistoryEvent) -> Void] = [:]

    /// 订阅事件，回调在主线程调用；返回的 token 交给 `removeObserver(_:)`。
    @discardableResult
    func observe(_ handler: @escaping (ClipboardHistoryEvent) -> Void) -> Observation {
        let token = UUID()
        handlers[token] = handler
        return token
    }

    func removeObserver(_ token: Observation) {
        handlers[token] = nil
    }

    func post(_ event: ClipboardHistoryEvent) {
        // 先取快照：订阅回调里可能又增删订阅。
        for handler in Array(handlers.values) {
            handler(event)
        }
    }
}
