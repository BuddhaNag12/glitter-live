import SwiftUI

enum LaunchIntro {
    /// Screenshot runs open straight onto a screen, so the intro would only get in the way.
    static var shouldPlay: Bool {
        #if DEBUG
        if DemoLaunch.isDemo || DemoLaunch.initialTab != nil { return false }
        #endif
        return true
    }
}

/// The logo reveal designed in Jitter (`Branding/logo-animated.json`): the ensō paints on, the mark glides left
/// and "Glitter Live" emerges from behind it. It starts on the plain launch screen and fades into the app.
struct LaunchIntroView: View {
    var onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set when the intro first appears, not when it's created: app startup can take a moment, and the
    /// animation shouldn't have run by the time it's on screen.
    @State private var start: Date?
    @State private var skippedAt: Date?

    private let art = LogoArtwork.shared

    /// Milliseconds, as in the Jitter timeline.
    private static let revealEnd = 1300.0
    private static let hold = 200.0
    private static let fade = 350.0
    private static let skipFade = 200.0

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = start.map { context.date.timeIntervalSince($0) * 1000 } ?? 0
            ZStack {
                Color("LaunchBackground").ignoresSafeArea()
                GeometryReader { geometry in
                    lockup(at: reduceMotion ? .infinity : elapsed)
                        .frame(width: art.width, height: LogoArtwork.height, alignment: .topLeading)
                        .scaleEffect(min(geometry.size.width * 0.84 / art.width, 1))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .opacity(reduceMotion ? Self.eased(progress(elapsed, 0, 250), .standard) : 1)
            }
            .opacity(1 - fadeOut(at: context.date))
        }
        .contentShape(Rectangle())
        // Nobody should have to sit through it.
        .onTapGesture { if skippedAt == nil { skippedAt = .now } }
        .task(id: skippedAt) {
            if start == nil { start = .now }
            let remaining = finishDate.timeIntervalSinceNow
            try? await Task.sleep(for: .seconds(max(remaining, 0)))
            if !Task.isCancelled { onFinish() }
        }
        .accessibilityElement()
        .accessibilityLabel("Glitter Live")
        .accessibilityAddTraits(.isImage)
    }

    // MARK: Timeline

    private var fadeStart: Date {
        if let skippedAt { return skippedAt }
        let reveal = reduceMotion ? 700.0 : Self.revealEnd + Self.hold
        return (start ?? .now).addingTimeInterval(reveal / 1000)
    }

    private var finishDate: Date {
        fadeStart.addingTimeInterval((skippedAt == nil ? Self.fade : Self.skipFade) / 1000)
    }

    private func fadeOut(at date: Date) -> Double {
        let duration = (skippedAt == nil ? Self.fade : Self.skipFade) / 1000
        return Self.eased(min(max(date.timeIntervalSince(fadeStart) / duration, 0), 1), .slowdown)
    }

    private func progress(_ elapsed: Double, _ from: Double, _ to: Double) -> Double {
        min(max((elapsed - from) / (to - from), 0), 1)
    }

    private enum Ease { case standard, slowdown }

    /// Jitter's "smooth" and "slowdown" curves.
    private static func eased(_ t: Double, _ ease: Ease) -> Double {
        switch ease {
        case .standard: t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .slowdown: 1 - pow(1 - t, 3)
        }
    }

    // MARK: Lockup

    private func lockup(at t: Double) -> some View {
        let ink = colorScheme == .dark ? Color.white : Color(hex: 0x0F172A)
        let blue = Color(hex: 0x3B82F6)
        let slate = Color(hex: 0x64748B)
        // The mark starts centred and glides left to make room for the words.
        let glide = Self.eased(progress(t, 450, 950), .standard)
        let shift = (art.width / 2 - LogoArtwork.markCenter.x) * (1 - glide)

        return ZStack(alignment: .topLeading) {
            wordmark(at: t, ink: ink, blue: blue)
                .mask(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: art.width, height: LogoArtwork.height)
                        .offset(x: LogoArtwork.emergeClipX + shift)
                }
            shine(at: t)
            pop(art.iSparkle, color: blue, around: art.iSparkleCenter, at: t, from: 950, to: 1100, scale: 0.2, turn: -45)
            mark(at: t, ink: ink, blue: blue, slate: slate)
                .offset(x: shift)
        }
    }

    private func mark(at t: Double, ink: Color, blue: Color, slate: Color) -> some View {
        let center = LogoArtwork.markCenter, s = LogoArtwork.markScale
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                art.enso.fill(blue)
                art.dots.fill(slate)
            }
            .mask(alignment: .topLeading) {
                BrushSweep(progress: Self.eased(progress(t, 0, 450), .standard), center: center, radius: 460 * s, start: LogoArtwork.brushStart.radians)
            }
            pop(art.star, color: ink, around: center, at: t, from: 80, to: 450, scale: 0.8, turn: -12)
            pop(art.blueSparkle, color: blue, around: CGPoint(x: center.x + 150 * s, y: center.y - 150 * s), at: t, from: 220, to: 450, scale: 0.3)
            pop(art.slateSparkle, color: slate, around: CGPoint(x: center.x - 138 * s, y: center.y + 150 * s), at: t, from: 280, to: 480, scale: 0.3)
        }
    }

    /// Each letter slides out from behind the ensō, one after another; "Live" arrives last and travels further.
    private func wordmark(at t: Double, ink: Color, blue: Color) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(art.letters.indices, id: \.self) { index in
                let isLive = index == art.letters.count - 1
                let begin = 500 + 30 * Double(index)
                let arrived = Self.eased(progress(t, begin, isLive ? 1130 : begin + 360), .slowdown)
                art.letters[index]
                    .fill(isLive ? blue : ink)
                    .offset(x: -(isLive ? 220 : 160) * (1 - arrived))
                    .opacity(arrived)
            }
        }
    }

    /// One soft band of light across the words, masked to their shapes.
    private func shine(at t: Double) -> some View {
        let travel = Self.eased(progress(t, 980, 1200), .standard)
        return Rectangle()
            .fill(.white)
            .frame(width: 160, height: 500)
            .rotationEffect(.degrees(20))
            .blur(radius: 30)
            .position(x: 850 + 1950 * travel + 80, y: LogoArtwork.height / 2)
            .opacity(0.65 * progress(t, 980, 1040))
            .frame(width: art.width, height: LogoArtwork.height)
            .mask(alignment: .topLeading) {
                art.letters.reduce(into: Path()) { $0.addPath($1) }.fill()
            }
    }

    /// Grows a shape in from a smaller size, optionally turning it into place.
    private func pop(_ path: Path, color: Color, around center: CGPoint, at t: Double, from: Double, to: Double, scale: Double, turn: Double = 0) -> some View {
        let shown = Self.eased(progress(t, from, to), .slowdown)
        return path.fill(color)
            .scaleEffect(scale + (1 - scale) * shown, anchor: art.anchor(center))
            .rotationEffect(.degrees(turn * (1 - shown)), anchor: art.anchor(center))
            .opacity(shown)
    }
}

/// A pie that opens clockwise from the brush's first touch, revealing the ensō as if it were being painted.
nonisolated private struct BrushSweep: Shape {
    var progress: Double
    let center: CGPoint
    let radius: CGFloat
    /// Screen angle of the brush's first touch.
    let start: Double

    func path(in rect: CGRect) -> Path {
        guard progress > 0 else { return Path() }
        // Starts a touch before the head so its rounded tip is revealed whole.
        let start = start - 0.12
        let sweep = (2 * .pi + 0.12) * progress
        let steps = max(Int(120 * progress), 2)
        var path = Path()
        path.move(to: center)
        for step in 0...steps {
            let angle = start + sweep * Double(step) / Double(steps)
            path.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
        }
        path.closeSubpath()
        return path
    }
}
