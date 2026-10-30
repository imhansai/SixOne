//
//  PanelPasteFlowTests.swift
//  SixOneTests
//  粘贴链路：权限/事件探测在改动任何东西之前失败；激活后只在目标真正回到前台时投递 ⌘V。
//

import AppKit
import Foundation
import Testing
@testable import SixOne

@Suite("粘贴链路")
@MainActor
struct PanelPasteFlowTests {
    @Test("没有辅助功能权限：提示并申请，不动剪贴板也不收面板")
    func permissionDeniedTouchesNothing() throws {
        let fixture = try PasteFixture()
        fixture.permission.granted = false
        let item = fixture.textItem("hello")
        try fixture.insert(item)

        fixture.flow.paste(item)

        #expect(fixture.noticeState.message != nil)
        #expect(fixture.harness.pasteboard.lastWrite == nil)
        #expect(fixture.hideCount == 0)
        #expect(fixture.scheduler.count == 0)
        #expect(fixture.revealed.isEmpty)
    }

    @Test("⌘V 事件建不出来：先失败，剪贴板与面板都不动")
    func eventCreationFailureTouchesNothing() throws {
        let fixture = try PasteFixture()
        fixture.eventPoster.canPost = false
        let item = fixture.textItem("hello")
        try fixture.insert(item)

        fixture.flow.paste(item)

        #expect(fixture.noticeState.message != nil)
        #expect(fixture.harness.pasteboard.lastWrite == nil)
        #expect(fixture.hideCount == 0)
        #expect(fixture.scheduler.count == 0)
        #expect(fixture.eventPoster.postedCount == 0)
    }

    @Test("目标已在前台：写回、收起、激活并按一次 ⌘V")
    func pastesWhenTargetIsAlreadyFrontmost() throws {
        let fixture = try PasteFixture()
        let item = fixture.textItem("hello")
        try fixture.insert(item)

        fixture.flow.paste(item)

        // 收起之后才轮到激活与投递。
        #expect(fixture.harness.pasteboard.lastWrite == .text("hello", rtf: nil))
        #expect(fixture.revealed == [item.id])
        #expect(fixture.hideCount == 1)
        #expect(fixture.scheduler.count == 1)
        #expect(fixture.apps.activated.isEmpty)

        fixture.scheduler.runNext()

        #expect(fixture.apps.yielded.map(\.processIdentifier) == [fixture.target.processIdentifier])
        #expect(fixture.apps.activated.map(\.processIdentifier) == [fixture.target.processIdentifier])
        #expect(fixture.eventPoster.postedCount == 1)
        #expect(fixture.feedback.beeps == 0)
        #expect(fixture.scheduler.count == 0)
    }

    @Test("目标稍后回到前台：轮询到它再投递")
    func waitsUntilTargetComesForward() throws {
        let fixture = try PasteFixture()
        fixture.apps.frontmostProcessIdentifier = 1
        let item = fixture.textItem("hello")
        try fixture.insert(item)

        fixture.flow.paste(item)
        fixture.scheduler.runNext()

        #expect(fixture.eventPoster.postedCount == 0)
        #expect(fixture.scheduler.count == 1, "目标还没到前台，应当排一次重试")

        fixture.apps.frontmostProcessIdentifier = fixture.target.processIdentifier
        fixture.clock.now = fixture.clock.now.addingTimeInterval(0.01)
        fixture.scheduler.runNext()

        #expect(fixture.eventPoster.postedCount == 1)
        #expect(fixture.feedback.beeps == 0)
        #expect(fixture.scheduler.count == 0)
    }

    @Test("目标已退出：不投递，响一声并把内容留在剪贴板")
    func terminatedTargetIsNotPastedInto() throws {
        let fixture = try PasteFixture()
        fixture.apps.terminated = true
        let item = fixture.textItem("hello")
        try fixture.insert(item)

        fixture.flow.paste(item)
        fixture.scheduler.runNext()

        #expect(fixture.eventPoster.postedCount == 0)
        #expect(fixture.feedback.beeps == 1)
        #expect(fixture.harness.pasteboard.lastWrite == .text("hello", rtf: nil))
        #expect(fixture.hideCount == 1)
    }

    @Test("等目标回前台超时：不投递，响一声")
    func timeoutAbandonsPaste() throws {
        let fixture = try PasteFixture()
        fixture.apps.frontmostProcessIdentifier = 1
        let item = fixture.textItem("hello")
        try fixture.insert(item)

        fixture.flow.paste(item)
        fixture.scheduler.runNext()

        fixture.clock.now = fixture.clock.now.addingTimeInterval(1)
        fixture.scheduler.runNext()

        #expect(fixture.eventPoster.postedCount == 0)
        #expect(fixture.feedback.beeps == 1)
        #expect(fixture.scheduler.count == 0)
    }

    @Test("没有上一个应用：不激活也不投递，响一声")
    func missingPreviousApplicationAbandons() throws {
        let fixture = try PasteFixture()
        fixture.previousApplicationValue = nil
        let item = fixture.textItem("hello")
        try fixture.insert(item)

        fixture.flow.paste(item)
        fixture.scheduler.runNext()

        #expect(fixture.apps.activated.isEmpty)
        #expect(fixture.eventPoster.postedCount == 0)
        #expect(fixture.feedback.beeps == 1)
    }

    @Test("普通粘贴保留富文本")
    func normalPasteKeepsRichText() throws {
        let fixture = try PasteFixture()
        let rtf = Data("{\\rtf1\\ansi hello}".utf8)
        let item = fixture.textItem("hello", rtf: rtf)
        try fixture.insert(item)

        fixture.flow.paste(item)

        #expect(fixture.harness.pasteboard.lastWrite == .text("hello", rtf: rtf))
    }

    @Test("纯文本粘贴：只写文字，不带富文本")
    func plainTextDropsRichText() throws {
        let fixture = try PasteFixture()
        let rtf = Data("{\\rtf1\\ansi hello}".utf8)
        let item = fixture.textItem("hello", rtf: rtf)
        try fixture.insert(item)

        fixture.flow.paste(item, asPlainText: true)

        #expect(fixture.harness.pasteboard.lastWrite == .text("hello", rtf: nil))
    }

    @Test("组内指定文件：只把那一个写回剪贴板")
    func fileIndexWritesOnlyThatFile() throws {
        let fixture = try PasteFixture()
        let file = try TemporaryFiles.makeFile(prefix: "sixone-paste", contents: "x")
        defer { try? FileManager.default.removeItem(at: file) }
        let item = ClipboardItem(kind: .file, filePaths: [file.path, "/tmp/another.txt"])
        try fixture.insert(item)

        fixture.flow.paste(item, fileIndex: 0)

        #expect(fixture.harness.pasteboard.lastWrite == .fileURLs([file]))
        #expect(fixture.hideCount == 1)
        #expect(fixture.revealed == [item.id])
    }

    @Test("组内指定文件不存在：提示并中止，不动剪贴板")
    func missingIndexedFileAborts() throws {
        let fixture = try PasteFixture()
        let item = ClipboardItem(kind: .file, filePaths: ["/tmp/sixone-missing-\(UUID().uuidString)"])
        try fixture.insert(item)

        fixture.flow.paste(item, fileIndex: 0)

        #expect(fixture.noticeState.message != nil)
        #expect(fixture.harness.pasteboard.lastWrite == nil)
        #expect(fixture.hideCount == 0)
        #expect(fixture.scheduler.count == 0)
    }

    @Test("整组粘贴：至少一个文件还在就放行，失联的按原路径回写")
    func groupPasteAllowsPartiallyMissingFiles() throws {
        let fixture = try PasteFixture()
        let file = try TemporaryFiles.makeFile(prefix: "sixone-paste-group", contents: "x")
        defer { try? FileManager.default.removeItem(at: file) }
        let missingPath = "/tmp/sixone-missing-\(UUID().uuidString)"
        let item = ClipboardItem(kind: .file, filePaths: [file.path, missingPath])
        try fixture.insert(item)

        fixture.flow.paste(item)

        #expect(fixture.harness.pasteboard.lastWrite == .fileURLs([
            file,
            URL(fileURLWithPath: missingPath),
        ]))
        #expect(fixture.hideCount == 1)
    }
}

// MARK: - 夹具与替身

@MainActor
private final class PasteFixture {
    let harness: ClipboardHarness
    let noticeState = NoticeState()
    let eventPoster = FakePasteEventPoster()
    let apps = FakePasteApplicationController()
    let permission = FakePastePermissionChecker()
    let scheduler = ManualPasteScheduler()
    let clock = FakePasteClock()
    let feedback = FakePasteFeedback()
    let target = NSRunningApplication.current
    var previousApplicationValue: NSRunningApplication?
    var hideCount = 0
    var revealed: [UUID] = []

    lazy var flow = PanelPasteFlow(
        manager: harness.manager,
        noticeState: noticeState,
        requestReveal: { [weak self] id in self?.revealed.append(id) },
        previousApplication: { [weak self] in self?.previousApplicationValue },
        hide: { [weak self] in self?.hideCount += 1 },
        environment: PanelPasteEnvironment(
            eventPoster: eventPoster,
            applicationController: apps,
            permissionChecker: permission,
            scheduler: scheduler,
            clock: clock,
            feedback: feedback
        )
    )

    init() throws {
        harness = try ClipboardHarness()
        previousApplicationValue = NSRunningApplication.current
        apps.frontmostProcessIdentifier = NSRunningApplication.current.processIdentifier
    }

    func insert(_ item: ClipboardItem) throws {
        harness.context.insert(item)
        try harness.context.save()
    }

    func textItem(_ text: String, rtf: Data? = nil) -> ClipboardItem {
        let item = ClipboardItem(kind: .text, text: text, attributedTextData: rtf)
        item.refreshTitleSnapshot()
        item.refreshContentKey()
        return item
    }
}

@MainActor
private final class FakePasteEventPoster: PasteEventPosting {
    var canPost = true
    private(set) var postedCount = 0

    func canPostPasteShortcut() -> Bool { canPost }

    func postPasteShortcut() {
        postedCount += 1
    }
}

@MainActor
private final class FakePasteApplicationController: PasteApplicationControlling {
    var isAppActive = true
    var frontmostProcessIdentifier: pid_t?
    var terminated = false
    private(set) var activated: [NSRunningApplication] = []
    private(set) var yielded: [NSRunningApplication] = []

    func yieldActivation(to application: NSRunningApplication) {
        yielded.append(application)
    }

    func activate(_ application: NSRunningApplication) {
        activated.append(application)
    }

    func isTerminated(_ application: NSRunningApplication) -> Bool {
        terminated
    }
}

@MainActor
private final class FakePastePermissionChecker: PastePermissionChecking {
    var granted = true

    func ensureGranted() -> Bool { granted }
}

@MainActor
private final class ManualPasteScheduler: PasteScheduling {
    struct Scheduled {
        let delay: TimeInterval
        let action: @MainActor () -> Void
    }

    private(set) var scheduled: [Scheduled] = []

    var count: Int { scheduled.count }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        scheduled.append(Scheduled(delay: delay, action: action))
    }

    func runNext() {
        guard !scheduled.isEmpty else { return }
        scheduled.removeFirst().action()
    }
}

@MainActor
private final class FakePasteClock: PasteClock {
    var now = Date(timeIntervalSinceReferenceDate: 0)
}

@MainActor
private final class FakePasteFeedback: PasteFeedback {
    private(set) var beeps = 0

    func beep() {
        beeps += 1
    }
}
