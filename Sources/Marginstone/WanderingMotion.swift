import Foundation
import CoreGraphics

/// Irregular, gently changing drift within a narrow band around the placed height.
struct WanderingMotion {
    private var baseline: CGFloat?
    private var horizontalSpeed = 0.0
    private var targetSpeed = 24.0
    private var verticalOffset = 0.0
    private var targetOffset = 0.0
    private var changeIn = 0.0

    mutating func reset(height: CGFloat) {
        baseline = height; verticalOffset = 0; targetOffset = 0; changeIn = 0
    }

    mutating func step(from point: CGPoint, dt: Double, area: CGRect, size: CGSize) -> CGPoint {
        if baseline == nil { baseline = point.y }
        let elapsed = min(0.1, max(0, dt))
        changeIn -= elapsed
        if changeIn <= 0 {
            let pause = Double.random(in: 0...1) < 0.15
            targetSpeed = pause ? 0 : Double.random(in: 12...44) * (Bool.random() ? 1 : -1)
            targetOffset = Double.random(in: -14...14)
            changeIn = Double.random(in: 1.2...4.5)
        }
        horizontalSpeed += (targetSpeed - horizontalSpeed) * (1 - exp(-elapsed / 0.7))
        verticalOffset += (targetOffset - verticalOffset) * (1 - exp(-elapsed / 1.3))
        let left = area.minX + 12
        let right = max(left, area.maxX - size.width - 12)
        var x = point.x + horizontalSpeed * elapsed
        if x >= right { x = right; horizontalSpeed = -abs(horizontalSpeed); targetSpeed = -abs(targetSpeed) }
        if x <= left { x = left; horizontalSpeed = abs(horizontalSpeed); targetSpeed = abs(targetSpeed) }
        let y = min(max((baseline ?? point.y) + verticalOffset, area.minY), max(area.minY, area.maxY - size.height))
        return CGPoint(x: x, y: y)
    }
}
