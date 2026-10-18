import AppKit
import CoreGraphics

/// The Dock's full-display overview overlay is visible through window metadata.
/// No screen images, window titles, or application contents are read.
@MainActor
final class MissionControlParking {
    private weak var view: CompanionView?
    private var timer: Timer?
    private var active = false
    private var missingSince: TimeInterval?
    init(view: CompanionView) {
        self.view = view
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }
    deinit { timer?.invalidate() }
    static func isOverview(windows: [[String: Any]], screens: [CGRect]) -> Bool {
        windows.contains { window in
            guard window[kCGWindowOwnerName as String] as? String == "Dock",
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0 > 0,
                  let values = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: values) else { return false }
            return screens.contains { screen in
                rect.width >= screen.width * 0.9 && rect.height >= screen.height * 0.9
            }
        }
    }
    private func update() {
        guard let view, let window = view.window else { return }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let now = ProcessInfo.processInfo.systemUptime
        if Self.isOverview(windows: windows, screens: NSScreen.screens.map(\.frame)) {
            missingSince = nil
            guard !active, window.isVisible, let area = window.screen?.visibleFrame else { return }
            active = true
            let origin = NSPoint(x: max(area.minX, area.maxX - window.frame.width - 18),
                                 y: max(area.minY, area.maxY - window.frame.height - 64))
            view.parkForOverview(at: origin)
        } else if active {
            if missingSince == nil { missingSince = now }
            // Avoid bouncing back during a short gap in the system animation.
            if now - (missingSince ?? now) >= 0.3 {
                active = false; missingSince = nil
                view.leaveOverview()
            }
        }
    }
}
