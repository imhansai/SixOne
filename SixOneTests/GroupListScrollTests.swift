//
//  GroupListScrollTests.swift
//  SixOneTests
//  组内列表按「行 + 上下留白」最小滚动，两端由文档边界钳住。

import Foundation
import Testing
@testable import SixOne

@Suite("文件组列表滚动几何")
struct FileGroupListScrollGeometryTests {
    private func rowRect(_ position: Int, count: Int) -> CGRect {
        let isFirst = position == 0
        let isLast = position == count - 1
        return CGRect(
            x: 0,
            y: isFirst
                ? 0
                : ClipboardLayout.groupListPadding + CGFloat(position) * ClipboardLayout.rowHeight,
            width: 300,
            height: ClipboardLayout.rowHeight
                + (isFirst ? ClipboardLayout.groupListPadding : 0)
                + (isLast ? ClipboardLayout.groupListPadding : 0)
        )
    }

    @Test("行完整可见且留白够：不动")
    func alreadyVisible() {
        let visible = CGRect(x: 0, y: 0, width: 300, height: 300)
        #expect(FileGroupListScrollGeometry.targetOriginY(
            rowRect: rowRect(1, count: 10),
            visible: visible,
            documentHeight: 2000
        ) == 0)
    }

    @Test("行在上方被切掉：向上滚到含留白的位置")
    func scrollsUp() {
        let visible = CGRect(x: 0, y: 40, width: 300, height: 300)
        #expect(FileGroupListScrollGeometry.targetOriginY(
            rowRect: rowRect(0, count: 10),
            visible: visible,
            documentHeight: 2000
        ) == 0)
    }

    @Test("行在下方被切掉：向下滚到含留白的位置")
    func scrollsDown() {
        let visible = CGRect(x: 0, y: 0, width: 300, height: 300)
        #expect(FileGroupListScrollGeometry.targetOriginY(
            rowRect: rowRect(5, count: 10),
            visible: visible,
            documentHeight: 2000
        ) == 64)
    }

    @Test("文档两端由边界钳住，留白仍然保留")
    func clampsAtDocumentEdges() {
        let visible = CGRect(x: 0, y: 0, width: 300, height: 200)
        #expect(FileGroupListScrollGeometry.targetOriginY(
            rowRect: rowRect(9, count: 10),
            visible: visible,
            documentHeight: 596
        ) == 396)

        let scrolled = CGRect(x: 0, y: 100, width: 300, height: 200)
        #expect(FileGroupListScrollGeometry.targetOriginY(
            rowRect: rowRect(0, count: 10),
            visible: scrolled,
            documentHeight: 596
        ) == 0)
    }
}
