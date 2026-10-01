import CoreText
import SwiftUI

/// The Glitter Live lockup as vector paths, in the 1000-unit-tall space of the brand artwork.
/// Same geometry as `scripts/render-icon.swift`, which draws the PNG, PDF and SVG logos.
struct LogoArtwork {
    static let shared = LogoArtwork()

    static let height: CGFloat = 1000
    static let markCenter = CGPoint(x: 500, y: 500)
    static let markScale: CGFloat = 760 / 1024
    /// The words emerge from behind the ensō, so they're clipped left of this line.
    static let emergeClipX: CGFloat = 812
    /// Where the brush first touches down, as a screen angle; the ensō paints clockwise from here.
    static let brushStart = Angle(radians: -.pi * 0.62)

    let width: CGFloat
    let enso: Path
    let dots: Path
    let star: Path
    let blueSparkle: Path
    let slateSparkle: Path
    /// G, l, ı, t, t, e, r, then "Live" as one piece.
    let letters: [Path]
    let iSparkle: Path
    let iSparkleCenter: CGPoint

    private init() {
        let center = Self.markCenter, s = Self.markScale
        enso = Self.ensoPath(center: center, scale: s)
        var dots = Path()
        for index in 0..<28 {
            let angle = CGFloat(index) / 28 * 2 * .pi
            let point = CGPoint(x: center.x + cos(angle) * 292 * s, y: center.y + sin(angle) * 292 * s)
            dots.addEllipse(in: CGRect(x: point.x - 9 * s, y: point.y - 9 * s, width: 18 * s, height: 18 * s))
        }
        self.dots = dots
        star = Self.sparkle(at: center, radius: 200 * s)
        blueSparkle = Self.sparkle(at: CGPoint(x: center.x + 150 * s, y: center.y - 150 * s), radius: 62 * s)
        slateSparkle = Self.sparkle(at: CGPoint(x: center.x - 138 * s, y: center.y + 150 * s), radius: 38 * s)

        let size: CGFloat = 320
        let font = CTFontCreateWithName("Inter-Bold" as CFString, size, nil)
        let capHeight = CTFontGetCapHeight(font)
        let baseline = Self.height / 2 + capHeight / 2
        let originX: CGFloat = 120 + 760 + 70
        let wordGap = size * 0.24

        let glitter = Self.line("Gl\u{0131}tter", font: font)
        let live = Self.line("Live", font: font)
        let glitterWidth = CTLineGetTypographicBounds(glitter, nil, nil, nil)
        let liveWidth = CTLineGetTypographicBounds(live, nil, nil, nil)
        let liveGlyphs = Self.glyphPaths(live, font: font, originX: originX + glitterWidth + wordGap, baseline: baseline)
        letters = Self.glyphPaths(glitter, font: font, originX: originX, baseline: baseline)
            + [liveGlyphs.reduce(into: Path()) { $0.addPath($1) }]

        let iStart = CTLineGetOffsetForStringIndex(glitter, 2, nil)
        let iEnd = CTLineGetOffsetForStringIndex(glitter, 3, nil)
        iSparkleCenter = CGPoint(x: originX + (iStart + iEnd) / 2, y: baseline - CTFontGetXHeight(font) - size * 0.2)
        iSparkle = Self.sparkle(at: iSparkleCenter, radius: size * 0.15)
        width = 120 * 2 + 760 + 70 + glitterWidth + wordGap + liveWidth
    }

    /// Any point, as a unit point of the artwork, for anchoring scale and rotation.
    func anchor(_ point: CGPoint) -> UnitPoint {
        UnitPoint(x: point.x / width, y: point.y / Self.height)
    }

    /// A solid tapered ensō: pressed thick at the start, lifting to a point as it closes the circle.
    private static func ensoPath(center: CGPoint, scale s: CGFloat) -> Path {
        let startAngle = CGFloat.pi * 0.62
        let sweep = 2 * CGFloat.pi * 0.965
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        for step in 0...360 {
            let t = CGFloat(step) / 360
            let angle = startAngle - sweep * t
            let radius = (400 - 10 * t) * s
            let press = pow(sin(CGFloat.pi * min(max(t * 0.94 + 0.06, 0), 1)), 0.55) * (1 - 0.45 * t)
            let half = (4 + 58 * press) * s / 2
            outer.append(CGPoint(x: center.x + cos(angle) * (radius + half), y: center.y - sin(angle) * (radius + half)))
            inner.append(CGPoint(x: center.x + cos(angle) * (radius - half), y: center.y - sin(angle) * (radius - half)))
        }
        var path = Path()
        path.addLines(outer + inner.reversed())
        path.closeSubpath()
        let head = CGPoint(x: center.x + cos(startAngle) * 400 * s, y: center.y - sin(startAngle) * 400 * s)
        let half = (4 + 58 * pow(sin(CGFloat.pi * 0.06), 0.55)) * s / 2
        path.addEllipse(in: CGRect(x: head.x - half, y: head.y - half, width: 2 * half, height: 2 * half))
        return path
    }

    /// A four-point glint: the "glitter" in the brand.
    private static func sparkle(at c: CGPoint, radius r: CGFloat) -> Path {
        let waist = r * 0.14
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + waist, y: c.y - waist))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + waist, y: c.y + waist))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - waist, y: c.y + waist))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - waist, y: c.y - waist))
        path.closeSubpath()
        return path
    }

    private static func line(_ string: String, font: CTFont) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    }

    /// One path per glyph, flipped from Core Text's y-up space onto the baseline.
    private static func glyphPaths(_ line: CTLine, font: CTFont, originX: CGFloat, baseline: CGFloat) -> [Path] {
        var paths: [Path] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: originX + position.x, ty: baseline - position.y)
                if let glyphPath = CTFontCreatePathForGlyph(font, glyph, &transform) {
                    paths.append(Path(glyphPath))
                }
            }
        }
        return paths
    }
}
