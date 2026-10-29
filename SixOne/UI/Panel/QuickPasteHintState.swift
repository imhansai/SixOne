//
//  QuickPasteHintState.swift
//  SixOne
//  按住 ⌘ / ⌘⇧ 时在完整可见行上显示快速粘贴编号；延时避开常用命令键的闪现。
//

import AppKit
import Observation

/// ⌘+数字快速粘贴的边界。
enum QuickPaste {
    /// 一屏完整可见行最多放 8 行，9 是给布局变化留的余量。
    static let rowLimit = 9

    /// 编号从完整可见范围的首行起算；范围外与超出上限返回 nil。
    static func shortcutNumber(forRow row: Int, in range: ClosedRange<Int>?) -> Int? {
        guard let range, range.contains(row) else { return nil }
        let number = row - range.lowerBound + 1
        return number <= rowLimit ? number : nil
    }
}

@Observable
final class QuickPasteHintState {
    /// 按住多久才显示：⌘C、⌘W 这类组合按下即用，不该闪出编号。
    static let defaultShowDelay: TimeInterval = 0.15

    private(set) var isShowing = false
    @ObservationIgnored private var pendingShow: DispatchWorkItem?
    /// `cancel()` 不保证延时闭包不被调用；代际让过期的那次自己退出。
    @ObservationIgnored private var generation = 0
    private let showDelay: TimeInterval

    init(showDelay: TimeInterval = QuickPasteHintState.defaultShowDelay) {
        self.showDelay = showDelay
    }

    /// 只认 ⌘ 与 ⌘⇧；⌥/⌃ 参与的组合立即收起。
    func handleModifiers(_ modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection([.command, .shift, .option, .control])
        guard flags == [.command] || flags == [.command, .shift] else {
            cancel()
            return
        }
        guard !isShowing, pendingShow == nil else { return }
        generation &+= 1
        let generation = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == generation else { return }
            self.pendingShow = nil
            self.isShowing = true
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: work)
    }

    /// 松开、按其它键、收面板或失去键盘焦点时调用。
    func cancel() {
        generation &+= 1
        pendingShow?.cancel()
        pendingShow = nil
        isShowing = false
    }
}
