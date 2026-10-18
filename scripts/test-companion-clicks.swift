import AppKit
import MarginstoneCore

// Test-only app dependencies; no installed resources or collection are accessed.
enum AppResources { static let bundle = Bundle.main }
struct AppFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

@main struct CompanionClickChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Disposable clipboard fixture", forType: .string)
        let view = CompanionView(frame: NSRect(x: 0, y: 0, width: 110, height: 110))
        var selectionReads = 0
        view.readClipboard = { preconditionFailure("Selection capture fell back to stale clipboard") }
        view.readSelection = { _ in
            selectionReads += 1
            return CapturePayload(text: "Disposable clipboard fixture")
        }
        var captures = 0
        var openings = 0
        view.capture = { payload in
            precondition(payload.text == "Disposable clipboard fixture")
            captures += 1
        }
        view.openCollection = { openings += 1 }
        func event(_ type: NSEvent.EventType, clicks: Int) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: 55, y: 55), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        precondition(view.acceptsFirstMouse(for: event(.leftMouseDown, clicks: 1)))
        view.mouseDown(with: event(.leftMouseDown, clicks: 1))
        view.mouseUp(with: event(.leftMouseUp, clicks: 1))
        view.mouseDown(with: event(.leftMouseDown, clicks: 2))
        view.mouseUp(with: event(.leftMouseUp, clicks: 2))
        try await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.2) * 1e9))
        precondition(captures == 1 && openings == 0 && selectionReads == 1)
        view.mouseDown(with: event(.leftMouseDown, clicks: 1))
        view.mouseUp(with: event(.leftMouseUp, clicks: 1))
        try await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.2) * 1e9))
        precondition(captures == 1 && openings == 1)
        var failures = 0
        view.captureFailed = { _ in failures += 1 }
        view.readSelection = { _ in throw AppFailure(message: "Fixture selection unavailable") }
        view.mouseDown(with: event(.leftMouseDown, clicks: 1))
        view.mouseUp(with: event(.leftMouseUp, clicks: 1))
        view.mouseDown(with: event(.leftMouseDown, clicks: 2))
        view.mouseUp(with: event(.leftMouseUp, clicks: 2))
        try await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.2) * 1e9))
        precondition(captures == 1 && failures == 1)
        let window = FloatingPanel(contentRect: NSRect(x: 100, y: 100, width: 110, height: 110), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = view
        view.staysNearSelection = true
        view.movesSideToSide = false
        let start = window.frame.origin
        let target = NSPoint(x: 500, y: 300)
        view.pointerLocation = { NSPoint(x: target.x + 55, y: target.y + 55) }
        view.moveBesideSelection(to: target)
        try await Task.sleep(nanoseconds: 140_000_000)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            precondition(window.frame.origin == start && window.alphaValue < 1)
        }
        try await Task.sleep(nanoseconds: 450_000_000)
        precondition(abs(window.frame.minX - target.x) < 1 && abs(window.frame.minY - target.y) < 1)
        precondition(window.alphaValue == 1)
        view.acknowledge()
        try await Task.sleep(nanoseconds: 1_300_000_000)
        precondition(abs(window.frame.minX - start.x) < 1 && abs(window.frame.minY - start.y) < 1)
        precondition(window.alphaValue == 1)
        view.moveBesideSelection(to: target)
        try await Task.sleep(nanoseconds: 600_000_000)
        let capturesBeforeDismiss = captures
        view.pointerLocation = { NSPoint(x: target.x + 400, y: target.y + 400) }
        try await Task.sleep(nanoseconds: 850_000_000)
        precondition(abs(window.frame.minX - start.x) < 1 && abs(window.frame.minY - start.y) < 1)
        precondition(captures == capturesBeforeDismiss && window.alphaValue == 1)
        let parked = NSPoint(x: 1200, y: 700)
        view.parkForOverview(at: parked)
        precondition(window.frame.origin == parked && !view.canFollowSelection)
        try await Task.sleep(nanoseconds: 300_000_000)
        precondition(window.frame.origin == parked)
        view.leaveOverview()
        try await Task.sleep(nanoseconds: 650_000_000)
        precondition(abs(window.frame.minX - start.x) < 1 && abs(window.frame.minY - start.y) < 1)
        print("Click capture, fade/return, pointer dismissal and overview parking checks passed.")
    }
}
