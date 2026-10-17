import AppKit
import ApplicationServices
import MarginstoneCore

/// Only invoked by an explicit double-click; never monitors selections or clipboard.
@MainActor
enum SelectionCapture {
    static func read(from application: NSRunningApplication?) async throws -> CapturePayload {
        guard let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated else {
            throw AppFailure(message: "Highlight text in another app, then double-click the companion. To save copied text instead, use Capture clipboard from its menu.")
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw AppFailure(message: "Allow Marginstone in System Settings → Privacy & Security → Accessibility, then try again. You can still copy text and use Capture clipboard from the companion’s menu.")
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 1)
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let element = unsafeBitCast(focused, to: AXUIElement.self)
            var selection: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selection) == .success,
               let text = selection as? String,
               !text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard text.utf8.count <= 2_000_000 else { throw AppFailure(message: "Choose a passage smaller than 2 MB.") }
                return CapturePayload(text: text, types: ["accessibility.selected-text"], sourceApp: application.bundleIdentifier ?? application.localizedName ?? "")
            }
        }
        // Some PDF viewers expose selection only through Copy. Require a fresh
        // clipboard change so an old excerpt or screenshot can never be substituted.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
            throw AppFailure(message: "Return to the app with your selection and double-click the companion again.")
        }
        let board = NSPasteboard.general
        let previous = board.changeCount
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            throw AppFailure(message: "Could not copy this selection. Use ⌘C and Capture clipboard from the companion’s menu.")
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(application.processIdentifier); up.postToPid(application.processIdentifier)
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 100_000_000)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else { break }
            if board.changeCount != previous {
                var payload = try CaptureReader.read(board)
                payload.sourceApp = application.bundleIdentifier ?? application.localizedName ?? ""
                return payload
            }
        }
        throw AppFailure(message: "This app did not provide the selection. Try ⌘C, then Capture clipboard from the companion’s menu.")
    }
}
