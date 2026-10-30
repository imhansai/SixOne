//
//  InteractiveImagePreview.swift
//  SixOne
//
//  图片预览：滚轮/捏合缩放、两指/拖拽平移、双击适配；缩放交给 NSScrollView。
//

import AppKit
import SwiftUI

struct InteractiveImagePreview: NSViewRepresentable {
    /// 图片身份；只有它变化才复位缩放，同一张图重算不打断交互。
    let identity: String
    /// 基准档位图（1×–2× 清晰）；放大超出范围时按需取更细档。
    let tier: PreviewImageDecoder.Tier
    var finerTier: (@Sendable (Int) async -> PreviewImageDecoder.Tier?)?

    func makeNSView(context: Context) -> ZoomableImageScrollView {
        ZoomableImageScrollView(tier: tier, identity: identity, finerTier: finerTier)
    }

    func updateNSView(_ view: ZoomableImageScrollView, context: Context) {
        view.finerTier = finerTier
        view.apply(tier, identity: identity)
    }
}

/// 可缩放图片视图；缩放状态在 magnification 里，仅在身份变化时复位。
final class ZoomableImageScrollView: NSScrollView {
    private let canvas = ImageCanvasView()

    private(set) var bitmapPixelSize = 0
    private(set) var displaySize = NSSize.zero
    private(set) var sourcePixelSize = NSSize.zero
    private(set) var fitMagnification: CGFloat = 1
    var finerTier: (@Sendable (Int) async -> PreviewImageDecoder.Tier?)?

    private var baseTier: PreviewImageDecoder.Tier?
    private var identity = ""
    private var hasFittedOnce = false
    /// 用户动过缩放/平移后不再自动适配，避免布局变化冲掉其操作。
    private var userAdjusted = false
    private var lastViewportSize = NSSize.zero
    private var isFitting = false

    private var requestedPixelSize = 0
    private var sourceExhausted = false
    private var upgradeTask: Task<Void, Never>?

    private var eventMonitor: Any?
    /// 当前手势持有者；切条目时只让最新视图消费，否则捏合会没反应。
    @MainActor private static weak var gestureOwner: ZoomableImageScrollView?
    /// 统一观察 magnification 变化，否则系统直接改倍率时会漏掉换档。
    private var magnificationObservation: NSKeyValueObservation?
    private var magnifyEndObserver: NSObjectProtocol?
    private var dragOrigin: NSPoint?
    private var isDragging = false
    /// 捏合接管状态：从内容区开始后持续到结束，越过内容边界也不中断。
    private var magnifyGate = MagnifyGate()

    init(
        tier: PreviewImageDecoder.Tier,
        identity: String,
        finerTier: (@Sendable (Int) async -> PreviewImageDecoder.Tier?)?
    ) {
        self.finerTier = finerTier
        super.init(frame: .zero)
        allowsMagnification = true
        // 关闭主轴锁定以支持自由斜向；代价是缩放状态下有已知抖动。
        usesPredominantAxisScrolling = false
        hasVerticalScroller = false
        hasHorizontalScroller = false
        drawsBackground = false
        borderType = .noBorder
        let clipView = CenteringClipView()
        // 必须显式关闭：scroll view 的设置不会传给替换后的 contentView。
        clipView.drawsBackground = false
        contentView = clipView
        documentView = canvas
        wantsLayer = true
        observeMagnification()
        apply(tier, identity: identity)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let magnifyEndObserver {
            NotificationCenter.default.removeObserver(magnifyEndObserver)
        }
    }

    /// KVO 与通知回调无隔离上下文；magnification 只在主线程改，故就地声明隔离。
    private func observeMagnification() {
        magnificationObservation = observe(\.magnification) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateTier() }
        }
        magnifyEndObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.magnifyGate.reset()
                self?.updateTier()
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - 内容

    /// 同一张图只换更细档，不冲掉细档也不复位缩放；身份变化才按换图重置。
    func apply(_ tier: PreviewImageDecoder.Tier, identity: String) {
        let isNewImage = identity != self.identity
        guard isNewImage || tier.pixelSize > bitmapPixelSize else { return }
        self.identity = identity
        baseTier = tier
        show(tier)
        guard isNewImage else { return }
        requestedPixelSize = 0
        sourceExhausted = false
        userAdjusted = false
        upgradeTask?.cancel()
        zoomToFit()
        needsLayout = true
    }

    private func show(_ tier: PreviewImageDecoder.Tier) {
        bitmapPixelSize = tier.pixelSize
        displaySize = tier.displaySize
        sourcePixelSize = tier.sourcePixelSize
        canvas.setBitmap(tier.bitmap, displaySize: tier.displaySize)
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? 2 }

    // MARK: - 适配与布局

    override func layout() {
        super.layout()
        let viewport = contentView.frame.size
        guard viewport.width > 0, viewport.height > 0 else { return }
        guard viewport != lastViewportSize || !hasFittedOnce else { return }
        lastViewportSize = viewport
        updateMagnificationLimits()
        if !hasFittedOnce || !userAdjusted {
            zoomToFit()
        }
        updateTier()
    }

    /// 是否处于适配窗口；按几何判断，不比对缓存值（系统会微调 clip bounds）。
    var isAtFit: Bool {
        guard hasFittedOnce, canvas.frame.width > 0, canvas.frame.height > 0 else { return false }
        let visible = contentView.bounds.size
        let tolerance = ClipboardLayout.geometryTolerance
        let fullyVisible = canvas.frame.width <= visible.width + tolerance
            && canvas.frame.height <= visible.height + tolerance
        let touchesEdge = abs(canvas.frame.width - visible.width) < tolerance
            || abs(canvas.frame.height - visible.height) < tolerance
        return fullyVisible && touchesEdge
    }

    private func zoomToFit() {
        guard !isFitting, canvas.frame.width > 0, canvas.frame.height > 0 else { return }
        guard contentView.frame.width > 0, contentView.frame.height > 0 else { return }
        isFitting = true
        defer { isFitting = false }
        // 先放开上下限，否则 magnify(toFit:) 会被默认最小值 0.25 夹掉。
        minMagnification = 0.0001
        maxMagnification = 10_000
        magnify(toFit: canvas.frame)
        fitMagnification = magnification
        hasFittedOnce = true
        userAdjusted = false
        lastViewportSize = contentView.frame.size
        updateMagnificationLimits()
        updateTier()
    }

    /// 上下限按适配倍率换算（1× = 适配、最大 8×）；下限须容得下实际大小。
    private func updateMagnificationLimits() {
        guard fitMagnification > 0 else { return }
        minMagnification = min(fitMagnification * 0.25, actualSizeMagnification)
        maxMagnification = fitMagnification * 8
    }

    // MARK: - 换档

    private func requiredPixelSize() -> Int {
        Int((max(displaySize.width, displaySize.height) * magnification * backingScale).rounded(.up))
    }

    private func updateTier() {
        if requestFinerTierIfNeeded() { return }
        releaseFinerTierIfUnneeded()
    }

    /// 超出基准档覆盖范围时请求更细档；返回是否已发起请求。
    private func requestFinerTierIfNeeded() -> Bool {
        guard let finerTier, !sourceExhausted else { return false }
        let needed = requiredPixelSize()
        let sourceLimit = Int(max(sourcePixelSize.width, sourcePixelSize.height).rounded())
        guard min(needed, sourceLimit) > bitmapPixelSize else { return false }
        // 留 20% 余量，避免临界点反复请求。
        guard needed > Int(Double(bitmapPixelSize) * 1.2), needed > requestedPixelSize else { return false }
        requestedPixelSize = needed
        upgradeTask?.cancel()
        upgradeTask = Task { [weak self] in
            // 捏合时尺寸每帧变化，等手停下再取。
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            let tier = await finerTier(needed)
            guard !Task.isCancelled else { return }
            self.requestedPixelSize = 0
            self.adopt(tier)
        }
        return true
    }

    private func adopt(_ tier: PreviewImageDecoder.Tier?) {
        guard let tier, tier.pixelSize > bitmapPixelSize else {
            sourceExhausted = true
            return
        }
        // 取图期间用户可能已缩回，别白留大位图。
        guard requiredPixelSize() > bitmapPixelSize else { return }
        show(tier)
        updateTier()
    }

    /// 缩回基准档时释放细档，避免大位图一直占内存。
    private func releaseFinerTierIfUnneeded() {
        guard let baseTier, bitmapPixelSize > baseTier.pixelSize else { return }
        guard requiredPixelSize() <= baseTier.pixelSize else { return }
        upgradeTask?.cancel()
        requestedPixelSize = 0
        sourceExhausted = false
        show(baseTier)
    }

    // MARK: - 事件

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            guard eventMonitor == nil else { return }
            // SwiftUI 宿主内收不到 magnify/smartMagnify，改在应用层捕获；不 override scrollWheel 以免退出响应式滚动。
            Self.gestureOwner = self
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.magnify, .smartMagnify, .scrollWheel]
            ) { [weak self] event in
                guard let self, self.shouldHandle(event) else { return event }
                return self.handle(event) ? nil : event
            }
        } else if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
            magnifyGate.reset()
            if Self.gestureOwner === self {
                Self.gestureOwner = nil
            }
        }
    }

    func shouldHandle(_ event: NSEvent) -> Bool {
        guard let window = self.window, event.window === window else { return false }
        guard Self.gestureOwner === self else {
            magnifyGate.reset()
            return false
        }

        guard event.type == .magnify else {
            return contains(windowPoint: event.locationInWindow)
        }
        return magnifyGate.shouldHandle(
            phase: event.phase,
            isInsideContent: contains(windowPoint: event.locationInWindow)
        )
    }

    /// 捏合接管：began 按起点决定，之后沿用；从留白开始则不接管。
    struct MagnifyGate {
        private var isHandling = false

        mutating func shouldHandle(phase: NSEvent.Phase, isInsideContent: Bool) -> Bool {
            if phase == .began {
                isHandling = isInsideContent
                return isHandling
            }
            if phase == .ended || phase == .cancelled {
                let wasHandling = isHandling
                isHandling = false
                return wasHandling
            }
            if phase.isEmpty {
                // 没有 phase 的捏合事件按单次处理；正常路径不会走到。
                return isInsideContent
            }
            return isHandling
        }

        mutating func reset() {
            isHandling = false
        }
    }

    func contains(windowPoint point: NSPoint) -> Bool {
        guard window != nil else { return false }
        return bounds.contains(convert(point, from: nil))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        canvas.needsDisplay = true
        updateTier()
    }

    /// 鼠标滚轮与 ⌘+滚动归缩放；精确增量（触控板/妙控鼠标）留给系统平移。
    static func zoomsOnScroll(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas
    }

    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .magnify:
            zoom(by: 1 + event.magnification, centeredAt: anchor(of: event))
            return true
        case .smartMagnify:
            toggleSmartZoom(centeredAt: anchor(of: event))
            return true
        case .scrollWheel:
            guard Self.zoomsOnScroll(event) else { return false }
            // 精确增量更细，步长分开取以保持手感一致。
            let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.08
            zoom(by: 1 + event.scrollingDeltaY * step, centeredAt: anchor(of: event))
            return true
        default:
            return false
        }
    }

    func zoom(by factor: CGFloat, centeredAt point: NSPoint) {
        guard factor > 0 else { return }
        userAdjusted = true
        setMagnification(magnification * factor, centeredAt: point)
        updateTier()
    }

    /// 智能缩放（两指双击）：适配 ⇄ 实际大小。
    func toggleSmartZoom(centeredAt point: NSPoint) {
        guard hasFittedOnce else { return }
        userAdjusted = true
        if isAtFit {
            setMagnification(actualSizeMagnification, centeredAt: point)
        } else {
            zoomToFit()
        }
        updateTier()
    }

    /// 实际大小的 magnification：1 源像素 = 1 设备像素。
    var actualSizeMagnification: CGFloat {
        guard displaySize.width > 0, displaySize.height > 0, backingScale > 0 else { return 1 }
        return max(
            sourcePixelSize.width / (displaySize.width * backingScale),
            sourcePixelSize.height / (displaySize.height * backingScale)
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            zoomToFit()
            return
        }
        dragOrigin = event.locationInWindow
        isDragging = true
        if canPan {
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, canPan, let previous = dragOrigin else { return }
        userAdjusted = true
        dragOrigin = event.locationInWindow
        // 位移换算成文档坐标（1 文档点 = magnification 视图点），否则拖拽跟不上指针。
        let scale = max(magnification, 0.0001)
        var destination = contentView.bounds.origin
        // 拖动方向与视口移动方向相反。
        destination.x -= (event.locationInWindow.x - previous.x) / scale
        destination.y -= (event.locationInWindow.y - previous.y) / scale
        contentView.scroll(to: destination)
        reflectScrolledClipView(contentView)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        isDragging = false
        NSCursor.arrow.set()
    }

    private var canPan: Bool {
        canvas.frame.width > contentView.bounds.width || canvas.frame.height > contentView.bounds.height
    }

    /// setMagnification 需要 clip view 坐标；用 contentView 换算，勿用窗口坐标。
    private func anchor(of event: NSEvent) -> NSPoint {
        contentView.convert(event.locationInWindow, from: nil)
    }
}

// MARK: - 画布

/// 只把位图放进 layer.contents，缩放交给 Core Animation。
/// 必须在 updateLayer() 里赋值，直接赋 contents 会被 AppKit 显示周期清掉。
private final class ImageCanvasView: NSView {
    private var bitmap: CGImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .trilinear
        layer?.minificationFilter = .trilinear
        layer?.isOpaque = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        layer?.contents = bitmap
        // CGImage 不带倍率，不设 contentsScale 会在 2× 屏上画糊。
        layer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    func setBitmap(_ bitmap: CGImage, displaySize: NSSize) {
        self.bitmap = bitmap
        setFrameSize(displaySize)
        needsDisplay = true
    }
}

private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if document.frame.width < rect.width {
            rect.origin.x = (document.frame.width - rect.width) / 2
        }
        if document.frame.height < rect.height {
            rect.origin.y = (document.frame.height - rect.height) / 2
        }
        return rect
    }
}
