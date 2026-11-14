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
/// and "Glitter Live" emerges from behind it. It starts on the plain launch screen, then the logo flies up into the
/// header as the app appears beneath it. When there's no header to land on (the onboarding is showing, or Reduce
/// Motion is on), it fades instead.
struct LaunchIntroView: View {
    var onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BrandLogoTarget.self) private var logoTarget: BrandLogoTarget?
    @AppStorage(OnboardingState.completedKey) private var hasCompletedOnboarding = false
    /// Set when the intro first appears, not when it's created: app startup can take a moment, and the
    /// animation shouldn't have run by the time it's on screen.
    @State private var start: Date?
    @State private var skippedAt: Date?
    /// Where the logo lands, fixed when the exit begins: the header is only laid out once the app is underneath.
    @State private var landing: CGRect?

    private let art = LogoArtwork.shared

    /// Milliseconds, as in the Jitter timeline.
    private static let revealEnd = 1300.0
    private static let hold = 200.0
    private static let fade = 350.0
    private static let skipFade = 200.0
    private static let flight = 650.0
    private static let skipFlight = 350.0

    /// The header logo (`renderAppBarLogo` in `scripts/render-icon.swift`) is the same artwork with the same type size,
    /// but its mark is smaller: 384 units tall, words starting at 448, against the intro's words at 950.
    private static let headerLogoSize = CGSize(width: 2131.519, height: 384)
    private static let headerWords = CGPoint(x: 448, y: 192)
    private static let introWords = CGPoint(x: 120 + 760 + 70, y: LogoArtwork.height / 2)
    /// The header's mark against the intro's (0.405 vs 0.742 of the 1024-unit artwork), and how far right its
    /// centre sits, in intro units, once the words line up.
    private static let landedMarkScale: CGFloat = (384.0 / 1024 * 1.08) / (760.0 / 1024)
    private static let landedMarkShift: CGFloat = 950 - (448 - 192) - LogoArtwork.markCenter.x

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = start.map { context.date.timeIntervalSince($0) * 1000 } ?? 0
            let exit = exitProgress(at: context.date, flying: landing != nil)
            ZStack {
                Color("LaunchBackground").ignoresSafeArea()
                    .opacity(landing == nil ? 1 : 1 - exit)
                GeometryReader { geometry in
                    let place = placement(in: geometry, landing: landing, progress: exit)
                    lockup(at: reduceMotion ? .infinity : elapsed, landing: landing == nil ? 0 : exit)
                        .frame(width: art.width, height: LogoArtwork.height, alignment: .topLeading)
                        .scaleEffect(place.scale)
                        .offset(place.offset)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .opacity(reduceMotion ? Self.eased(progress(elapsed, 0, 250), .standard) : 1)
            }
            .opacity(landing == nil ? 1 - exit : 1)
        }
        .contentShape(Rectangle())
        // Nobody should have to sit through it.
        .onTapGesture { if skippedAt == nil, start != nil, Date.now < fadeStart { skippedAt = .now } }
        .task(id: skippedAt) {
            if start == nil { start = .now }
            try? await Task.sleep(for: .seconds(max(fadeStart.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            landing = headerLogoFrame
            try? await Task.sleep(for: .seconds(max(finishDate.timeIntervalSinceNow, 0)))
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

    /// The header logo as drawn, when the logo can fly there. The image fits inside its frame, so a narrow header
    /// draws it shorter than the frame, centred.
    private var headerLogoFrame: CGRect? {
        guard !reduceMotion, hasCompletedOnboarding, let frame = logoTarget?.frame, frame.width > 0, frame.height > 0 else { return nil }
        let unit = min(frame.width / Self.headerLogoSize.width, frame.height / Self.headerLogoSize.height)
        let size = CGSize(width: Self.headerLogoSize.width * unit, height: Self.headerLogoSize.height * unit)
        return CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func exitDuration(flying: Bool) -> Double {
        (flying ? (skippedAt == nil ? Self.flight : Self.skipFlight) : (skippedAt == nil ? Self.fade : Self.skipFade)) / 1000
    }

    private var finishDate: Date {
        fadeStart.addingTimeInterval(exitDuration(flying: landing != nil))
    }

    private func exitProgress(at date: Date, flying: Bool) -> Double {
        let t = min(max(date.timeIntervalSince(fadeStart) / exitDuration(flying: flying), 0), 1)
        return Self.eased(t, flying ? .standard : .slowdown)
    }

    /// Centred on the launch screen, then (as `progress` runs to 1) scaled and moved so the words sit exactly on
    /// the header logo's words.
    private func placement(in geometry: GeometryProxy, landing: CGRect?, progress p: Double) -> (scale: CGFloat, offset: CGSize) {
        let start = min(geometry.size.width * 0.84 / art.width, 1)
        guard let landing, p > 0 else { return (start, .zero) }
        let end = landing.height / Self.headerLogoSize.height
        let scale = start + (end - start) * p
        let box = geometry.frame(in: .global)
        // Where the words begin when the lockup is centred at scale `s` with no offset.
        func centred(_ s: CGFloat) -> CGPoint {
            CGPoint(x: box.width / 2 + (Self.introWords.x - art.width / 2) * s,
                    y: box.height / 2 + (Self.introWords.y - LogoArtwork.height / 2) * s)
        }
        let from = centred(start)
        let to = CGPoint(x: landing.minX - box.minX + Self.headerWords.x * end, y: landing.minY - box.minY + Self.headerWords.y * end)
        let natural = centred(scale)
        return (scale, CGSize(width: from.x + (to.x - from.x) * p - natural.x, height: from.y + (to.y - from.y) * p - natural.y))
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

    /// `landing` runs from 0 to 1 as the logo flies to the header, shrinking the mark to the header's proportions.
    private func lockup(at t: Double, landing: Double) -> some View {
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
                .scaleEffect(1 - (1 - Self.landedMarkScale) * landing, anchor: art.anchor(LogoArtwork.markCenter))
                .offset(x: shift + Self.landedMarkShift * landing)
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
