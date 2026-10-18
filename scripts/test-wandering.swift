import Foundation
import CoreGraphics

@main struct WanderingChecks {
    static func main() {
        var motion = WanderingMotion()
        let area = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 110, height: 110)
        let region = WanderingMotion.originBounds(area: area, size: size)
        var point = WanderingMotion.home(area: area, size: size)
        var minY = point.y; var maxY = point.y
        var reversed = false; var previousDelta = 0.0
        for _ in 0..<18000 {
            let next = motion.step(from: point, dt: 1.0/30, area: area, size: size)
            precondition(area.contains(CGRect(origin: next, size: size)))
            precondition(next.x >= region.minX && next.x <= region.maxX)
            precondition(next.y >= region.minY && next.y <= region.maxY)
            precondition(abs(next.x - point.x) < 2)
            let delta = next.x - point.x
            if delta * previousDelta < 0 { reversed = true }
            if abs(delta) > 0.01 { previousDelta = delta }
            minY = min(minY, next.y); maxY = max(maxY, next.y)
            point = next
        }
        precondition(maxY - minY > 2 && reversed)
        motion.reset()
        point = motion.step(from: CGPoint(x: 700, y: 600), dt: 1.0/30, area: area, size: size)
        precondition(point.x >= region.minX && point.y >= region.minY)
        // AppKit rounds each window move. Keep passing rounded coordinates back,
        // as a real panel does, and ensure slow motion still accumulates.
        var roundedMotion = WanderingMotion()
        var rounded = WanderingMotion.home(area: area, size: size)
        var distance = 0.0
        for _ in 0..<1800 {
            let next = roundedMotion.step(from: rounded, dt: 1.0/30, area: area, size: size)
            let displayed = CGPoint(x: next.x.rounded(), y: next.y.rounded())
            distance += abs(displayed.x - rounded.x)
            rounded = displayed
        }
        precondition(distance > 30)
        print("Corner confinement, irregular motion and subpixel accumulation checks passed.")
    }
}
