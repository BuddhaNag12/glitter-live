import Foundation

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

    /// The value that `rubberBand` turns into `resisted`, so a gesture can pick up from wherever an edge was drawn.
    static func unrubberBand(_ resisted: CGFloat, in range: ClosedRange<CGFloat>, dimension: CGFloat) -> CGFloat {
        func original(_ shown: CGFloat) -> CGFloat {
            let constant: CGFloat = 0.55
            let shown = min(shown, dimension * 0.99)
            return shown * dimension / (constant * (dimension - shown))
        }
        if resisted < range.lowerBound { return range.lowerBound - original(range.lowerBound - resisted) }
        if resisted > range.upperBound { return range.upperBound + original(resisted - range.upperBound) }
        return resisted
    }
}

/// A critically damped spring that can be read at any instant, so a gesture can catch it mid-flight
/// where SwiftUI's animations never report their on-screen value.
nonisolated struct CriticalSpring: Equatable {
    var from: CGFloat
    var to: CGFloat
    /// Points per second, straight from the finger at release.
    var velocity: CGFloat = 0
    /// Seconds to settle, as in Apple's response parameter.
    var response: Double = 0.4

    func value(after elapsed: TimeInterval) -> CGFloat {
        let omega = 2 * .pi / response
        let offset = from - to
        return to + (offset + (velocity + omega * offset) * elapsed) * exp(-omega * elapsed)
    }
}
