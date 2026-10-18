import Foundation
import CoreGraphics

/// Gentle, irregular motion confined to a small upper-right corner area.
struct WanderingMotion {
    private var preciseX: CGFloat?
    private var horizontalSpeed = 0.0
    private var targetSpeed = 12.0
    private var verticalOffset = 0.0
    private var targetOffset = 0.0
    private var changeIn = 0.0

    mutating func reset() {
        preciseX = nil; verticalOffset = 0; targetOffset = 0; changeIn = 0
    }

    mutating func step(from point: CGPoint, dt: Double, area: CGRect, size: CGSize) -> CGPoint {
        let region = Self.originBounds(area: area, size: size)
        let elapsed = min(0.1, max(0, dt))
        changeIn -= elapsed
        if changeIn <= 0 {
            let pause = Double.random(in: 0...1) < 0.15
            targetSpeed = pause ? 0 : Double.random(in: 6...20) * (Bool.random() ? 1 : -1)
            targetOffset = Double.random(in: -12...12)
            changeIn = Double.random(in: 1.2...4.5)
        }
        horizontalSpeed += (targetSpeed - horizontalSpeed) * (1 - exp(-elapsed / 0.7))
        verticalOffset += (targetOffset - verticalOffset) * (1 - exp(-elapsed / 1.3))
        let left = region.minX
        let right = region.maxX
        var x = (preciseX ?? point.x) + horizontalSpeed * elapsed
        if x >= right { x = right; horizontalSpeed = -abs(horizontalSpeed); targetSpeed = -abs(targetSpeed) }
        if x <= left { x = left; horizontalSpeed = abs(horizontalSpeed); targetSpeed = abs(targetSpeed) }
        preciseX = x
        let y = min(max(region.midY + verticalOffset, region.minY), region.maxY)
        return CGPoint(x: x, y: y)
    }
    static func originBounds(area: CGRect, size: CGSize) -> CGRect {
        let right = max(area.minX, area.maxX - size.width - 18)
        let top = max(area.minY, area.maxY - size.height - 18)
        let left = max(area.minX, right - 80)
        let bottom = max(area.minY, top - 28)
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }
    static func home(area: CGRect, size: CGSize) -> CGPoint {
        let region = originBounds(area: area, size: size)
        return CGPoint(x: region.midX, y: region.midY)
    }

}
