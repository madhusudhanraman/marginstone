import AppKit
import ApplicationServices

/// Responds only to completed mouse drags. It never copies or saves passages.
@MainActor
final class SelectionFollower {
    private weak var view: CompanionView?
    private var mouseMonitor: Any?
    private var dragStart: NSPoint?
    private var dragMoved = false
    init(view: CompanionView) {
        self.view = view
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            let point = NSEvent.mouseLocation
            let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            Task { @MainActor in self?.mouseGesture(type: type, point: point, bundle: bundle) }
        }

    }
    deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    }
    private func mouseGesture(type: NSEvent.EventType, point: NSPoint, bundle: String?) {
        guard let bundle, bundle != Bundle.main.bundleIdentifier else {
            dragStart = nil; dragMoved = false
            return
        }
        switch type {
        case .leftMouseDown:
            dragStart = point; dragMoved = false
        case .leftMouseDragged:
            if let start = dragStart, hypot(point.x - start.x, point.y - start.y) > 8 {
                dragMoved = true
            }
        case .leftMouseUp:
            defer { dragStart = nil; dragMoved = false }
            guard dragMoved else { return }
            if bundle != "com.apple.Preview" {
                update()
                return
            }
            guard let view, view.canFollowSelection,
                  let window = view.window, window.isVisible,
                  !window.frame.contains(point),
                  let area = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame else { return }
            view.staysNearSelection = true
            let origin = Self.origin(selection: nil, pointer: point, size: window.frame.size, area: area)
            view.moveBesideSelection(to: origin)

        default: break
        }
    }
    private func update() {
        guard let view, view.canFollowSelection, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        // Wait until the selection gesture is finished, rather than chasing a drag.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        var candidates: [AXUIElement] = []
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            candidates.append(unsafeBitCast(focused, to: AXUIElement.self))
        }
        let pointerLocation = NSEvent.mouseLocation
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(appElement, Float(pointerLocation.x), Float(primaryTop - pointerLocation.y), &hit) == .success,
           let hit { candidates.append(hit) }
        var found: (AXUIElement, CFTypeRef?, CFRange, String)?
        for candidate in candidates {
            var current: AXUIElement? = candidate
            for _ in 0..<5 {
                guard let element = current else { break }
                AXUIElementSetMessagingTimeout(element, 0.15)
                var subrole: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
                if subrole as? String == kAXSecureTextFieldSubrole as String { return }
                var rangeValue: CFTypeRef?
                var range = CFRange(location: 0, length: 0)
                if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
                   let value = rangeValue, CFGetTypeID(value) == AXValueGetTypeID() {
                    _ = AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range)
                }
                var selected: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected)
                let text = (selected as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if range.length > 0 || !text.isEmpty { found = (element, rangeValue, range, text); break }
                var parent: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                      let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
                current = unsafeBitCast(parent, to: AXUIElement.self)
            }
            if found != nil { break }
        }
        guard let (element, rangeValue, range, _) = found else {
            view.staysNearSelection = false
            return
        }
        var bounds: CGRect?
        if range.length > 0, let rangeValue {
            var value: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &value) == .success,
               let value, CFGetTypeID(value) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgRect, &rect), !rect.isEmpty,
                   rect.origin.x.isFinite, rect.origin.y.isFinite {
                    // Accessibility uses top-left coordinates on the primary display.
                    let top = NSScreen.screens.first?.frame.maxY ?? 0
                    bounds = CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
                }
            }
        }
        let pointer = NSEvent.mouseLocation
        let screen = bounds.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
            ?? NSScreen.screens.first { $0.frame.contains(pointer) }
        guard let area = screen?.visibleFrame, let window = view.window, window.isVisible else { return }
        let origin = Self.origin(selection: bounds, pointer: pointer, size: window.frame.size, area: area)
        view.staysNearSelection = true
        view.moveBesideSelection(to: origin)
    }
    static func origin(selection: CGRect?, pointer: NSPoint, size: NSSize, area: NSRect) -> NSPoint {
        let x = pointer.x - size.width / 2
        let y = pointer.y - size.height / 2
        return NSPoint(x: min(max(x, area.minX), max(area.minX, area.maxX - size.width)),
                       y: min(max(y, area.minY), max(area.minY, area.maxY - size.height)))
    }
}
