import Foundation
import CoreGraphics

@main struct WanderingChecks {
    static func main() {
        var motion = WanderingMotion()
        let area = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 110, height: 110)
        var point = CGPoint(x: 700, y: 400)
        var minY = point.y; var maxY = point.y
        var reversed = false; var previousDelta = 0.0
        for _ in 0..<18000 {
            let next = motion.step(from: point, dt: 1.0/30, area: area, size: size)
            precondition(area.contains(CGRect(origin: next, size: size)))
            precondition(abs(next.y - 400) <= 14.01)
            precondition(abs(next.x - point.x) < 2)
            let delta = next.x - point.x
            if delta * previousDelta < 0 { reversed = true }
            if abs(delta) > 0.01 { previousDelta = delta }
            minY = min(minY, next.y); maxY = max(maxY, next.y)
            point = next
        }
        precondition(maxY - minY > 2 && reversed)
        motion.reset(height: 600)
        point = motion.step(from: CGPoint(x: 700, y: 600), dt: 1.0/30, area: area, size: size)
        precondition(abs(point.y - 600) < 1)
        print("Irregular movement, narrow vertical band, smooth steps and dragged-height reset passed.")
    }
}
