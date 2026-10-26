//
//  ImagePreviewTests.swift
//  SixOneTests
//  图片预览：缩放/档位不被重算冲掉、缩回放细档、位图落层、背景透明、拖拽与滚轮。

import AppKit
import SwiftUI
import Testing
@testable import SixOne

@Suite("图片预览")
@MainActor
struct ImagePreviewTests {
    @Test("body 重算不复位缩放（列表图片条目的真路径）")
    func keepsZoomAcrossBodyUpdates() async throws {
        let context = try TestPanel.context()
        let item = ClipboardItem(kind: .image, imageData: Self.makePNGData(), contentType: "PNG")
        let (hosting, window) = Self.makeHost(item: item, context: context)
        defer { window.orderOut(nil) }

        let appeared = await Wait.until { Self.previewView(in: hosting)?.bitmapPixelSize ?? 0 > 0 }
        let view = try #require(
            appeared ? Self.previewView(in: hosting) : nil,
            "没等到图片预览视图"
        )

        view.setMagnification(view.magnification * 2, centeredAt: .zero)
        await Wait.settle(milliseconds: 50)
        let zoomed = view.magnification
        #expect(zoomed > view.fitMagnification, "缩放没生效")

        context.previewState.isEditing = true
        await Wait.settle(milliseconds: 100)

        #expect(view.magnification == zoomed, "body 重算把缩放复位了")
    }

    @Test("手势区只覆盖图片视图，留白与路径条不接管")
    func gestureAreaStaysInsideContentView() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
        window.contentView = root
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))

        let bitmap = try #require(Self.makeCGImage(pixels: 10))
        let tier = PreviewImageDecoder.Tier(
            bitmap: bitmap,
            displaySize: NSSize(width: 10, height: 10),
            sourcePixelSize: NSSize(width: 10, height: 10)
        )
        let imageView = ZoomableImageScrollView(tier: tier, identity: "test", finerTier: nil)
        let inset = ClipboardLayout.contentInset
        let gap = ClipboardLayout.pathBarInset
        let bar = ClipboardLayout.pathBarHeight
        imageView.frame = NSRect(
            x: inset,
            y: bar + gap,
            width: 300 - inset * 2,
            height: 240 - inset - gap - bar
        )
        root.addSubview(imageView)
        defer { window.orderOut(nil) }

        #expect(imageView.contains(windowPoint: NSPoint(x: 150, y: 130)), "内容区应生效")
        #expect(!imageView.contains(windowPoint: NSPoint(x: 9, y: 130)), "左侧留白不该生效")
        #expect(!imageView.contains(windowPoint: NSPoint(x: 291, y: 130)), "右侧留白不该生效")
        #expect(!imageView.contains(windowPoint: NSPoint(x: 150, y: 239)), "顶部留白不该生效")
        #expect(!imageView.contains(windowPoint: NSPoint(x: 150, y: 26)), "路径条上方间距不该生效")
        #expect(!imageView.contains(windowPoint: NSPoint(x: 150, y: 10)), "路径条不该生效")
        #expect(!imageView.contains(windowPoint: NSPoint(x: 400, y: 400)), "窗口外不该生效")
    }

    @Test("捏合从内容区开始后，指针越过路径条仍持续到结束")
    func magnifyGateKeepsHandlingAfterLeavingContent() {
        var gate = ZoomableImageScrollView.MagnifyGate()

        let beforeBegin = gate.shouldHandle(phase: .changed, isInsideContent: true)
        let beganInside = gate.shouldHandle(phase: .began, isInsideContent: true)
        let crossedPathBar = gate.shouldHandle(phase: .changed, isInsideContent: false)
        let endedOutside = gate.shouldHandle(phase: .ended, isInsideContent: false)
        let afterEnd = gate.shouldHandle(phase: .changed, isInsideContent: true)

        #expect(!beforeBegin, "没开始就不该接管")
        #expect(beganInside, "从内容区开始应接管")
        #expect(crossedPathBar, "越过路径条不该中断")
        #expect(endedOutside, "结束事件也要收尾")
        #expect(!afterEnd, "结束后不该继续接管")
    }

    @Test("从留白或路径条开始的捏合不接管")
    func magnifyGateIgnoresGesturesStartingOutsideContent() {
        var gate = ZoomableImageScrollView.MagnifyGate()

        let beganOutside = gate.shouldHandle(phase: .began, isInsideContent: false)
        let enteredLater = gate.shouldHandle(phase: .changed, isInsideContent: true)
        let cancelled = gate.shouldHandle(phase: .cancelled, isInsideContent: false)
        let afterCancel = gate.shouldHandle(phase: .changed, isInsideContent: true)

        #expect(!beganOutside)
        #expect(!enteredLater, "途中进入内容区也不该接管")
        #expect(!cancelled)
        #expect(!afterCancel)
    }

    @Test("没有相位信息的捏合按单次事件处理")
    func magnifyGateTreatsPhaselessEventAsSingleShot() {
        var gate = ZoomableImageScrollView.MagnifyGate()

        let inside = gate.shouldHandle(phase: [], isInsideContent: true)
        let outside = gate.shouldHandle(phase: [], isInsideContent: false)
        let afterwards = gate.shouldHandle(phase: .changed, isInsideContent: true)

        #expect(inside)
        #expect(!outside)
        #expect(!afterwards, "单次事件不应留下状态")
    }

    @Test("取消后重置，下一轮捏合重新按起点判定")
    func magnifyGateResetsOnCancel() {
        var gate = ZoomableImageScrollView.MagnifyGate()
        let beganInside = gate.shouldHandle(phase: .began, isInsideContent: true)
        let cancelled = gate.shouldHandle(phase: .cancelled, isInsideContent: true)
        let afterCancel = gate.shouldHandle(phase: .changed, isInsideContent: true)
        let nextGestureOutside = gate.shouldHandle(phase: .began, isInsideContent: false)

        #expect(beganInside)
        #expect(cancelled)
        #expect(!afterCancel)
        #expect(!nextGestureOutside)
    }

    @Test("换到细档位后，body 重算不会把它冲回基准档")
    func keepsFinerTierAcrossBodyUpdates() async throws {
        let (model, hosting, window) = try Self.makeProbe()
        defer { window.orderOut(nil) }

        let view = try await Self.waitForFittedView(in: hosting)
        #expect(view.bitmapPixelSize == 40, "基准档没进去")

        view.zoom(by: 2, centeredAt: .zero)
        let upgraded = await Wait.until { view.bitmapPixelSize == 400 }
        #expect(upgraded, "放大后没换成细档位")
        let zoomed = view.magnification

        model.tick += 1
        await Wait.settle(milliseconds: 100)

        #expect(view.bitmapPixelSize == 400, "body 重算把细档位图冲回基准档了")
        #expect(view.magnification == zoomed, "body 重算把缩放复位了")
        #expect(view.displaySize == Self.probeDisplaySize, "显示尺寸被改了")
    }

    @Test("缩回去就放掉细档、换回基准档；再放大还能换上去")
    func zoomingOutReleasesTheFinerTier() async throws {
        let (_, hosting, window) = try Self.makeProbe(
            basePixels: 1536,
            finerPixels: 3072,
            sourcePixels: 3072,
            displaySize: NSSize(width: 1200, height: 800)
        )
        defer { window.orderOut(nil) }

        let view = try await Self.waitForFittedView(in: hosting)
        #expect(view.bitmapPixelSize == 1536, "基准档没进去")

        view.zoom(by: 2, centeredAt: .zero)
        #expect(await Wait.until { view.bitmapPixelSize == 3072 }, "放大后没换成细档")
        let zoomed = view.magnification

        view.zoom(by: 0.25, centeredAt: .zero)   // 缩回适配窗口以下
        #expect(await Wait.until { view.bitmapPixelSize == 1536 }, "缩回去没放掉细档（大位图一直挂着）")
        #expect(view.magnification != zoomed, "换回基准档动了缩放")
        #expect(view.displaySize == NSSize(width: 1200, height: 800), "显示尺寸被改了")

        view.zoom(by: 8, centeredAt: .zero)
        #expect(await Wait.until { view.bitmapPixelSize == 3072 }, "再放大换不回细档")
    }

    @Test("源图给不出更细的档就不去解（小图放大不白解一次）")
    func doesNotAskForTiersBeyondTheSource() async throws {
        let (_, hosting, window) = try Self.makeProbe(basePixels: 40, finerPixels: 400, sourcePixels: 40)
        defer { window.orderOut(nil) }

        let view = try await Self.waitForFittedView(in: hosting)
        view.zoom(by: 4, centeredAt: .zero)
        await Wait.settle(milliseconds: 400)   // 远超 150ms 换档防抖

        #expect(view.bitmapPixelSize == 40, "源图给不出更细的，却还是换了档")
    }

    @Test("两指双击：适配 ⇄ 实际大小")
    func smartZoomTogglesActualSize() async throws {
        let (_, hosting, window) = try Self.makeProbe(basePixels: 40, finerPixels: 40)
        defer { window.orderOut(nil) }

        let view = try await Self.waitForFittedView(in: hosting)
        #expect(
            abs(view.magnification - view.actualSizeMagnification) > 0.01,
            "夹具里适配与实际大小应当不同"
        )
        #expect(view.isAtFit, "初始应当处于适配状态")

        view.toggleSmartZoom(centeredAt: .zero)
        await Wait.settle(milliseconds: 50)
        #expect(
            abs(view.magnification - view.actualSizeMagnification) < 0.01,
            "没切到实际大小（\(view.magnification) vs \(view.actualSizeMagnification)）"
        )
        #expect(!view.isAtFit, "实际大小不是适配状态")

        view.toggleSmartZoom(centeredAt: .zero)
        await Wait.settle(milliseconds: 50)
        #expect(view.isAtFit, "没切回适配窗口")
        #expect(abs(view.magnification - view.actualSizeMagnification) > 0.01, "切回适配后仍是实际大小")
    }

    @Test("预览背景透明：两层都不画自己的背景")
    func backgroundStaysTransparent() async throws {
        let (_, hosting, window) = try Self.makeProbe(basePixels: 40, finerPixels: 40)
        defer { window.orderOut(nil) }

        let view = try await Self.waitForView(in: hosting)
        // 任何一层画背景，图外都会变成白底。
        #expect(!view.drawsBackground, "scroll view 不该画背景")
        #expect(!view.contentView.drawsBackground, "clip view 不该画背景")
    }

    @Test("视口变化：没交互过就继续跟随，交互过就不动")
    func viewportChangesRespectUserZoom() async throws {
        let (_, hosting, window) = try Self.makeProbe(basePixels: 40, finerPixels: 40)
        defer { window.orderOut(nil) }

        let view = try await Self.waitForFittedView(in: hosting)

        window.setContentSize(NSSize(
            width: ClipboardLayout.panelWidth - 120,
            height: ClipboardLayout.panelHeight - 85
        ))
        hosting.layoutSubtreeIfNeeded()
        await Wait.settle(milliseconds: 100)
        #expect(view.isAtFit, "视口变小后没继续适配（图会被裁掉一块）")

        view.zoom(by: 0.9995, centeredAt: .zero)
        let zoomed = view.magnification
        #expect(zoomed != view.fitMagnification, "缩放没生效")
        window.setContentSize(ClipboardLayout.panelSize)
        hosting.layoutSubtreeIfNeeded()
        await Wait.settle(milliseconds: 100)
        #expect(
            view.magnification == zoomed,
            "重新布局把用户的缩放冲掉了（\(view.magnification) vs \(zoomed)）"
        )
    }

    @Test("拖拽平移：按住的那个点在拖动中原位不动")
    func draggingKeepsTheGrabbedPointUnderCursor() async throws {
        let (_, hosting, window) = try Self.makeProbe(basePixels: 40, finerPixels: 40)
        defer { window.orderOut(nil) }

        let view = try await Self.waitForFittedView(in: hosting)
        view.zoom(by: 4, centeredAt: .zero)   // 放大到有平移余量
        await Wait.settle(milliseconds: 50)

        let start = NSPoint(x: 320, y: 270)
        let moved = NSPoint(x: start.x + 40, y: start.y + 30)
        view.mouseDown(with: try #require(Self.mouseEvent(.leftMouseDown, at: start)))
        let grabbed = view.contentView.convert(start, from: nil)
        view.mouseDragged(with: try #require(Self.mouseEvent(.leftMouseDragged, at: moved)))
        let underCursor = view.contentView.convert(moved, from: nil)

        #expect(
            abs(underCursor.x - grabbed.x) < 0.5 && abs(underCursor.y - grabbed.y) < 0.5,
            "抓取点跑掉了：\(grabbed) → \(underCursor)（位移被放大或缩小了）"
        )
    }

    @Test("位图进到图层的 contents，且扛得住显示与重新布局")
    func bitmapReachesTheLayer() async throws {
        let (_, hosting, window) = try Self.makeProbe(basePixels: 40, finerPixels: 40)
        defer { window.orderOut(nil) }

        let view = try await Self.waitForFittedView(in: hosting)
        let appeared = await Wait.until { Self.layerContents(of: view) != nil }
        #expect(appeared, "位图没进 layer.contents")

        // 改视口并显示后 contents 仍须在；直接赋 contents 会被 AppKit 顶掉，走 updateLayer。
        window.displayIfNeeded()
        window.setContentSize(NSSize(
            width: ClipboardLayout.panelWidth - 120,
            height: ClipboardLayout.panelHeight - 85
        ))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        await Wait.settle(milliseconds: 50)

        #expect(Self.layerContents(of: view) != nil, "显示/重新布局把 layer.contents 清掉了")
    }

    @Test("斜向平移不被锁轴")
    func diagonalPanningIsNotAxisLocked() async throws {
        let (_, hosting, window) = try Self.makeProbe(basePixels: 40, finerPixels: 40)
        defer { window.orderOut(nil) }

        let view = try await Self.waitForView(in: hosting)
        // AppKit 默认锁主轴，斜向双指会一次只走一个轴。
        #expect(!view.usesPredominantAxisScrolling, "锁了主轴：斜向平移会一次只动一个轴")
    }

    @Test("滚轮缩放、⌘+滚动缩放、触控板两指留给系统平移")
    func scrollIntent() throws {
        #expect(
            ZoomableImageScrollView.zoomsOnScroll(try #require(Self.scrollEvent(precise: false))),
            "鼠标滚轮应当缩放"
        )
        #expect(
            ZoomableImageScrollView.zoomsOnScroll(try #require(Self.scrollEvent(precise: true, command: true))),
            "⌘+滚动应当缩放"
        )
        #expect(
            !ZoomableImageScrollView.zoomsOnScroll(try #require(Self.scrollEvent(precise: true))),
            "触控板两指应当留给系统平移"
        )
    }

    // MARK: - 夹具

    private static let probeDisplaySize = NSSize(width: 40, height: 40)

    @Observable
    @MainActor
    final class PreviewProbeModel {
        var tick = 0
    }

    private struct PreviewProbeHost: View {
        let base: PreviewImageDecoder.Tier
        let finer: PreviewImageDecoder.Tier
        let model: PreviewProbeModel

        var body: some View {
            let _ = model.tick   // 读 tick，让 body 依赖它
            InteractiveImagePreview(identity: "probe", tier: base) { _ in finer }
        }
    }

    private static func makeProbe(
        basePixels: Int = 40,
        finerPixels: Int = 400,
        sourcePixels: Int = 80,
        displaySize: NSSize = probeDisplaySize
    ) throws -> (model: PreviewProbeModel, hosting: NSHostingView<AnyView>, window: NSWindow) {
        let model = PreviewProbeModel()
        let size = NSSize(width: ClipboardLayout.panelWidth, height: ClipboardLayout.panelHeight)
        let hosting = NSHostingView(rootView: AnyView(
            PreviewProbeHost(
                base: try probeTier(pixels: basePixels, sourcePixels: sourcePixels, displaySize: displaySize),
                finer: try probeTier(pixels: finerPixels, sourcePixels: sourcePixels, displaySize: displaySize),
                model: model
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        ))
        return (model, hosting, host(hosting, size: size))
    }

    private static func probeTier(
        pixels: Int,
        sourcePixels: Int,
        displaySize: NSSize = probeDisplaySize
    ) throws -> PreviewImageDecoder.Tier {
        PreviewImageDecoder.Tier(
            bitmap: try #require(makeCGImage(pixels: pixels)),
            displaySize: displaySize,
            sourcePixelSize: NSSize(width: sourcePixels, height: sourcePixels)
        )
    }

    private static func waitForView(in hosting: NSView) async throws -> ZoomableImageScrollView {
        let appeared = await Wait.until { previewView(in: hosting) != nil }
        return try #require(appeared ? previewView(in: hosting) : nil, "没找到图片预览视图")
    }

    private static func waitForFittedView(in hosting: NSView) async throws -> ZoomableImageScrollView {
        let fitted = await Wait.until { previewView(in: hosting)?.isAtFit ?? false }
        return try #require(fitted ? previewView(in: hosting) : nil, "没等到适配窗口")
    }

    private static func makeHost(
        item: ClipboardItem,
        context: PanelContext
    ) -> (NSHostingView<AnyView>, NSWindow) {
        let size = NSSize(width: ClipboardLayout.panelWidth, height: ClipboardLayout.panelHeight)
        let hosting = NSHostingView(rootView: AnyView(
            PreviewDetailView(item: item)
                .frame(width: size.width, height: size.height)
                .environment(context)
        ))
        return (hosting, host(hosting, size: size))
    }

    private static func host(_ hosting: NSView, size: NSSize) -> NSWindow {
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        return window
    }

    private static func previewView(in view: NSView) -> ZoomableImageScrollView? {
        if let preview = view as? ZoomableImageScrollView { return preview }
        for subview in view.subviews {
            if let found = previewView(in: subview) { return found }
        }
        return nil
    }

    private static func layerContents(of view: ZoomableImageScrollView) -> Any? {
        view.documentView?.layer?.contents
    }

    private static func makePNGData(width: Int = 20, height: Int = 10) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }

    private static func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    /// 合成滚动事件：pixel 对应触控板，line 对应滚轮，即 hasPreciseScrollingDeltas 判据。
    private static func scrollEvent(precise: Bool, command: Bool = false) -> NSEvent? {
        guard let source = CGEventSource(stateID: .privateState),
              let event = CGEvent(
                  scrollWheelEvent2Source: source,
                  units: precise ? .pixel : .line,
                  wheelCount: 1,
                  wheel1: 3,
                  wheel2: 0,
                  wheel3: 0
              )
        else { return nil }
        if command {
            event.flags = .maskCommand
        }
        return NSEvent(cgEvent: event)
    }

    private static func makeCGImage(pixels: Int) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context?.makeImage()
    }
}
