import AppKit
import NautilusCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor
final class NautilusView: NSView {
    var movesSideToSide = true
    var capture: ((CapturePayload) throws -> Void)?
    var openCollection: (() -> Void)?
    var positionChanged: (() -> Void)?
    private var shell: NSImage?
    private var companion = Companion.selected
    private let bands: [NSImage]
    private var timer: Timer?
    private var tracking: NSTrackingArea?
    private var hovering = false
    private var receiving = false
    private var mouseStart = NSPoint.zero
    private var windowStart = NSPoint.zero
    private var moving = false
    private var previousTime = ProcessInfo.processInfo.systemUptime
    private var reverseAt = ProcessInfo.processInfo.systemUptime + 18
    private var velocity = 0.0
    private var targetVelocity = 3.4
    private var angle = 0.0
    private var travelDirection: CGFloat = 1
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
        setAccessibilityLabel("\(companion.name). Drop selected text to save it. Click to open the collection.")
        toolTip = "Drop selected text to save. Click for your collection. Drag the shell to move it. Right-click for Capture Clipboard."
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { [weak self] _ in
            guard let view = self else { return }
            Task { @MainActor in view.tick() }
        }
    }
    func setCompanion(_ value: Companion) {
        companion = value; shell = value.image; angle = 0; capturedAt = nil
        setAccessibilityLabel("\(value.name). Drop selected text to save it. Click to open the collection.")
        toolTip = "Drop selected text to save. Click for your collection. Drag to move. Right-click for Capture Clipboard."
        needsDisplay = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate() }
    override func accessibilityPerformPress() -> Bool { openCollection?(); return true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next); tracking = next
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { mouseStart = NSEvent.mouseLocation; windowStart = window?.frame.origin ?? .zero; moving = false }
    override func mouseDragged(with event: NSEvent) {
        let delta = NSPoint(x: NSEvent.mouseLocation.x-mouseStart.x, y: NSEvent.mouseLocation.y-mouseStart.y)
        if abs(delta.x)+abs(delta.y)>4 { moving = true }
        guard moving, let window else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? window.screen ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        window.setFrameOrigin(NSPoint(x: min(max(windowStart.x+delta.x, area.minX), area.maxX-window.frame.width), y: min(max(windowStart.y+delta.y, area.minY), area.maxY-window.frame.height)))
        positionChanged?()
    }
    override func mouseUp(with event: NSEvent) { if !moving { openCollection?() }; moving = false }
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
        } catch { NSSound.beep(); openCollection?(); return false }
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { receiving = false }
    func acknowledge() {
        let options = (0..<5).filter { $0 != activeBand }
        activeBand = options.randomElement() ?? 0; capturedAt = ProcessInfo.processInfo.systemUptime
        NSAccessibility.post(element: self, notification: .valueChanged)
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0, now-previousTime)); previousTime = now
        if now >= reverseAt { targetVelocity = (targetVelocity > 0 ? -1.0 : 1.0) * Double.random(in: 2.8...4.2); reverseAt = now + Double.random(in: 18...34) }
        velocity += (targetVelocity-velocity) * min(1, dt/2.4)
        let acknowledging = capturedAt.map { now-$0 < 1.5 } ?? false
        if !hovering && !receiving && !moving && !acknowledging && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            angle = (angle+velocity*dt).truncatingRemainder(dividingBy: 360)
            if movesSideToSide, let window, let area = window.screen?.visibleFrame {
                let left = area.minX + 12
                let right = max(left, area.maxX - window.frame.width - 12)
                var x = window.frame.minX + travelDirection * 32 * CGFloat(dt)
                if x >= right { x = right; travelDirection = -1 }
                if x <= left { x = left; travelDirection = 1 }
                window.setFrameOrigin(NSPoint(x: x, y: min(max(window.frame.minY, area.minY), area.maxY-window.frame.height)))
            }
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: angle * .pi/180)
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
