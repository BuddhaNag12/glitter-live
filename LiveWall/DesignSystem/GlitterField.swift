import SwiftUI

/// Faint specks and a few four-point sparkles that slowly twinkle behind the content.
/// Holds still with Reduce Motion, or on screens that have motion of their own.
struct GlitterField: View {
    var isAnimated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Twinkling is slow, so 15 fps looks smooth at a fraction of the cost.
        let holdsStill = reduceMotion || !isAnimated
        TimelineView(.animation(minimumInterval: 1 / 15, paused: holdsStill)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let isDark = colorScheme == .dark
                let tint = isDark ? Color.white : Color(hex: 0x64748B)
                let strength = isDark ? 0.75 : 0.3
                for speck in Speck.all {
                    let twinkle = holdsStill ? 0.6 : 0.5 + 0.5 * sin(time * speck.speed + speck.phase)
                    let center = CGPoint(x: speck.x * size.width, y: speck.y * size.height)
                    let path = speck.isSparkle
                        ? Self.sparkle(at: center, radius: speck.size * 3.2)
                        : Path(ellipseIn: CGRect(x: center.x - speck.size / 2, y: center.y - speck.size / 2, width: speck.size, height: speck.size))
                    canvas.fill(path, with: .color(tint.opacity(speck.brightness * twinkle * strength)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func sparkle(at c: CGPoint, radius r: CGFloat) -> Path {
        let waist = r * 0.16
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + waist, y: c.y - waist))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + waist, y: c.y + waist))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - waist, y: c.y + waist))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - waist, y: c.y - waist))
        return path
    }
}

private struct Speck {
    let x: Double
    let y: Double
    let size: Double
    let speed: Double
    let phase: Double
    let brightness: Double
    let isSparkle: Bool

    /// Fixed positions from a seeded generator, so the pattern is the same on every launch.
    static let all: [Speck] = {
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        return (0..<72).map { index in
            Speck(
                x: next(), y: next(),
                size: 0.8 + next() * 1.4,
                speed: 0.6 + next() * 1.6,
                phase: next() * 2 * .pi,
                brightness: 0.35 + next() * 0.65,
                isSparkle: index % 12 == 0
            )
        }
    }()
}
