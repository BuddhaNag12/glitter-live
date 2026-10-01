import SwiftUI

extension View {
    /// A soft sheen that passes over a placeholder while its content loads.
    func shimmer(_ isActive: Bool = true) -> some View {
        modifier(Shimmer(isActive: isActive))
    }

    /// Placeholders inside share this space, so scrolling doesn't shift their sheens out of step.
    func shimmerCoordinateSpace() -> some View {
        coordinateSpace(.named(Shimmer.space))
    }
}

/// One band of light crosses the page at a fixed speed, reaching lower placeholders a moment later,
/// so a row of chips or cards reads as a single light passing over them rather than separate sweeps.
private struct Shimmer: ViewModifier {
    static let space = "shimmer"
    private static let sweep = 1.3
    private static let period = 2.0
    private static let band: CGFloat = 200
    /// Wide enough to cross the largest iPhone screen.
    private static let travel: CGFloat = 480

    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isTabSelected) private var isTabSelected
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay {
            // With Reduce Motion the placeholder's shape alone says something is coming.
            if isActive && !reduceMotion {
                GeometryReader { geometry in
                    let origin = geometry.frame(in: .named(Self.space)).origin
                    let delay = Double(origin.y) / 1600
                    TimelineView(.animation(paused: !isTabSelected)) { context in
                        let time = context.date.timeIntervalSinceReferenceDate - delay
                        let progress = min(time.truncatingRemainder(dividingBy: Self.period) / Self.sweep, 1)
                        let bandX = -Self.band + progress * (Self.travel + Self.band)
                        LinearGradient(colors: [.clear, highlight, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: Self.band)
                            .offset(x: bandX - origin.x)
                    }
                }
                // Drawn only over the placeholder's own pixels, so the sheen follows its shape.
                .blendMode(.sourceAtop)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .compositingGroup()
    }

    private var highlight: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.6)
    }
}
