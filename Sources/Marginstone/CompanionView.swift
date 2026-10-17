import AppKit
import MarginstoneCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor
final class CompanionView: NSView {
    var movesSideToSide = true
    var staysNearSelection = false
    var canFollowSelection: Bool { !hovering && !receiving && !moving && !capturingSelection && travel == nil }
    var capture: ((CapturePayload) throws -> Void)?
    var captureFailed: ((Error) -> Void)?
    var openCollection: (() -> Void)?
    var readSelection: ((NSRunningApplication?) async throws -> CapturePayload)?
    private var selectionApplication: NSRunningApplication?
    private var capturingSelection = false
    var readClipboard: () throws -> CapturePayload = { try CaptureReader.read(.general) }
    var positionChanged: (() -> Void)?
    private var shell: NSImage?
    private var companion = Companion.selected
    private let bands: [NSImage]
    private var timer: Timer?
    private var tracking: NSTrackingArea?
    private var hovering = false
    private var displayScale: CGFloat = 0.65
    private var receiving = false
    private var mouseStart = NSPoint.zero
    private var windowStart = NSPoint.zero
    private var moving = false
    private var pendingClick: Task<Void, Never>?
    private var travel: (destination: NSPoint, began: TimeInterval, relocated: Bool)?
    private var restingOrigin: NSPoint?
    private var returnAt: TimeInterval?
    private var pointerAwaySince: TimeInterval?
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }
    func moveBesideSelection(to destination: NSPoint) {
        guard let window else { return }
        if restingOrigin == nil { restingOrigin = window.frame.origin }
        returnAt = nil; pointerAwaySince = nil
        relocate(to: destination)
    }
    private func relocate(to destination: NSPoint) {
        guard let window else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            travel = nil; window.alphaValue = 1; window.setFrameOrigin(destination)
        } else {
            travel = (destination, ProcessInfo.processInfo.systemUptime, false)
        }
    }
    private var previousTime = ProcessInfo.processInfo.systemUptime
    private var reverseAt = ProcessInfo.processInfo.systemUptime + 18
    private var velocity = 0.0
    private var targetVelocity = 3.4
    private var angle = 0.0
    private var wandering = WanderingMotion()
    private var capturedAt: TimeInterval?
    private var activeBand = -1
    override init(frame: NSRect) {
        func resource(_ name: String) -> NSImage? {
            AppResources.bundle.url(forResource: name, withExtension: "png", subdirectory: "Resources").flatMap { NSImage(contentsOf: $0) }
        }
        shell = Companion.selected.image
        bands = (0..<5).compactMap { resource("band-\($0)") }
        super.init(frame: frame)
        registerForDraggedTypes(CaptureReader.supported)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel("\(companion.name). Drop text or double-click to save highlighted text. Click to open the collection.")
        toolTip = "Highlight text, then double-click to save. Click for your collection. Right-click for Capture clipboard."
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { [weak self] _ in
            guard let view = self else { return }
            Task { @MainActor in view.tick() }
        }
    }
    func setCompanion(_ value: Companion) {
        companion = value; shell = value.image; angle = 0; capturedAt = nil
        setAccessibilityLabel("\(value.name). Drop text or double-click to save highlighted text. Click to open the collection.")
        toolTip = "Highlight text, then double-click to save. Click for your collection. Right-click for Capture clipboard."
        needsDisplay = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate(); pendingClick?.cancel() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { openCollection?(); return true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next); tracking = next
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {
        travel = nil; window?.alphaValue = 1
        if event.clickCount == 1 { selectionApplication = NSWorkspace.shared.frontmostApplication }
        pendingClick?.cancel(); mouseStart = NSEvent.mouseLocation; windowStart = window?.frame.origin ?? .zero; moving = false }
    override func mouseDragged(with event: NSEvent) {
        let delta = NSPoint(x: NSEvent.mouseLocation.x-mouseStart.x, y: NSEvent.mouseLocation.y-mouseStart.y)
        if abs(delta.x)+abs(delta.y)>4 { moving = true }
        guard moving, let window else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? window.screen ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        window.setFrameOrigin(NSPoint(x: min(max(windowStart.x+delta.x, area.minX), area.maxX-window.frame.width), y: min(max(windowStart.y+delta.y, area.minY), area.maxY-window.frame.height)))
        wandering.reset(height: window.frame.minY)
        positionChanged?()
    }
    override func mouseUp(with event: NSEvent) {
        defer { moving = false }
        guard !moving else { return }
        if event.clickCount == 2 {
            pendingClick?.cancel()
            guard !capturingSelection else { return }
            capturingSelection = true
            let application = selectionApplication
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.capturingSelection = false }
                do {
                    guard let capture = self.capture else { return }
                    let payload: CapturePayload
                    if let readSelection = self.readSelection { payload = try await readSelection(application) }
                    else { payload = try self.readClipboard() }
                    try capture(payload)
                    self.acknowledge()
                } catch { self.captureFailed?(error); NSSound.beep(); self.openCollection?() }
            }
        } else if event.clickCount == 1 {
            pendingClick = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(NSEvent.doubleClickInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.openCollection?()
            }
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSourceOperationMask.contains(.copy), (try? CaptureReader.read(sender.draggingPasteboard)) != nil else { return [] }
        receiving = true; return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { receiving ? .copy : [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { receiving = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { receiving }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        receiving = false
        do {
            guard let capture else { return false }
            try capture(CaptureReader.read(sender.draggingPasteboard)); acknowledge(); return true
        } catch { captureFailed?(error); NSSound.beep(); openCollection?(); return false }
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { receiving = false }
    func acknowledge() {
        let options = (0..<5).filter { $0 != activeBand }
        activeBand = options.randomElement() ?? 0; capturedAt = ProcessInfo.processInfo.systemUptime
        if restingOrigin != nil { returnAt = ProcessInfo.processInfo.systemUptime + 0.65 }
        NSAccessibility.post(element: self, notification: .valueChanged)
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0, now-previousTime)); previousTime = now
        if restingOrigin != nil, travel == nil, returnAt == nil,
           !capturingSelection, !moving, !receiving, let window {
            if window.frame.insetBy(dx: -18, dy: -18).contains(pointerLocation()) {
                pointerAwaySince = nil
            } else {
                if pointerAwaySince == nil { pointerAwaySince = now }
                if now - (pointerAwaySince ?? now) >= 0.18 { returnAt = now }
            }
        }
        if let returnAt, now >= returnAt, let home = restingOrigin {
            self.returnAt = nil; restingOrigin = nil; pointerAwaySince = nil
            staysNearSelection = false
            relocate(to: home)
        }
        if let travel, let window {
            let elapsed = max(0, now - travel.began)
            if elapsed < 0.22 {
                window.alphaValue = 1 - elapsed / 0.22
            } else {
                if !travel.relocated {
                    window.setFrameOrigin(travel.destination)
                    self.travel?.relocated = true
                }
                window.alphaValue = min(1, (elapsed - 0.22) / 0.28)
                if elapsed >= 0.5 { window.alphaValue = 1; self.travel = nil }
            }
        }
        if now >= reverseAt { targetVelocity = (targetVelocity > 0 ? -1.0 : 1.0) * Double.random(in: 2.8...4.2); reverseAt = now + Double.random(in: 18...34) }
        velocity += (targetVelocity-velocity) * min(1, dt/2.4)
        let acknowledging = capturedAt.map { now-$0 < 1.5 } ?? false
        let targetScale: CGFloat = (hovering || receiving || moving || acknowledging) ? 1 : 0.65
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            displayScale = targetScale
        } else {
            displayScale += (targetScale - displayScale) * CGFloat(1 - exp(-dt / 0.12))
        }
        if !hovering && !receiving && !moving && !acknowledging && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            angle = (angle+velocity*dt).truncatingRemainder(dividingBy: 360)
            if movesSideToSide, !staysNearSelection, travel == nil, let window, let area = window.screen?.visibleFrame {
                window.setFrameOrigin(wandering.step(from: window.frame.origin, dt: dt, area: area, size: window.frame.size))
            }
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: angle * .pi/180)
        context.scaleBy(x: displayScale, y: displayScale)
        let imageRect = NSRect(x: -bounds.width*0.45, y: -bounds.height*0.45, width: bounds.width*0.9, height: bounds.height*0.9)
        NSGraphicsContext.current?.imageInterpolation = .high
        let size = shell?.size ?? NSSize(width: 1, height: 1)
        let scale = min(imageRect.width / max(1, size.width), imageRect.height / max(1, size.height))
        let fitted = NSRect(x: -size.width*scale/2, y: -size.height*scale/2, width: size.width*scale, height: size.height*scale)
        shell?.draw(in: fitted)
        if companion != .nautilus, let capturedAt {
            let t = ProcessInfo.processInfo.systemUptime-capturedAt
            let opacity = max(0, min(1, t/0.2, (1.45-t)/0.55))
            shell?.draw(in: fitted, from: .zero, operation: .multiply, fraction: CGFloat(opacity*0.35))
        }
        if companion == .nautilus, let capturedAt, bands.indices.contains(activeBand) {
            let t = ProcessInfo.processInfo.systemUptime-capturedAt
            let opacity = t < 0.22 ? t/0.22 : (t < 0.9 ? 1 : max(0, (1.45-t)/0.55))
            bands[activeBand].draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: CGFloat(min(1,max(0,opacity))))
        }
        context.restoreGState()
    }
}
