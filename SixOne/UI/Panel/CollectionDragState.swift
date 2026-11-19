//
//  CollectionDragState.swift
//  SixOne
//
//  分组拖拽状态：筛选条上报，焦点判定据此避免拖拽出窗口时收起面板。
//

import Foundation

final class CollectionDragState {
    /// 是否正按住筛选条拖动。
    var isDragging = false {
        didSet {
            guard isDragging != oldValue else { return }
            onChange?(isDragging)
        }
    }

    /// 拖拽开始 / 结束通知。
    var onChange: ((_ isDragging: Bool) -> Void)?
}
