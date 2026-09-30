import CoreGraphics

/// Gesture physics from Apple's "Designing Fluid Interfaces".
nonisolated enum Motion {
    /// How far a flick carries before it comes to rest, like a decelerating scroll view.
    static func projection(of velocity: CGFloat, decelerationRate: CGFloat = 0.99) -> CGFloat {
        velocity / 1000 * decelerationRate / (1 - decelerationRate)
    }

    /// Past a bound the value follows less and less, so an edge feels soft rather than frozen.
    static func rubberBand(_ value: CGFloat, in range: ClosedRange<CGFloat>, dimension: CGFloat) -> CGFloat {
        func resisted(_ overshoot: CGFloat) -> CGFloat {
            let constant: CGFloat = 0.55
            return overshoot * dimension * constant / (dimension + constant * overshoot)
        }
        if value < range.lowerBound { return range.lowerBound - resisted(range.lowerBound - value) }
        if value > range.upperBound { return range.upperBound + resisted(value - range.upperBound) }
        return value
    }

    /// SwiftUI springs take velocity as a fraction of the distance left, so a release keeps the finger's speed.
    static func relativeVelocity(_ velocity: CGSize, from start: CGSize, to end: CGSize) -> Double {
        let dx = end.width - start.width, dy = end.height - start.height
        let distanceSquared = dx * dx + dy * dy
        guard distanceSquared > 1 else { return 0 }
        let relative = (velocity.width * dx + velocity.height * dy) / distanceSquared
        return min(max(relative, -30), 30)
    }
}
