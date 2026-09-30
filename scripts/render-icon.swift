import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Usage: swift scripts/render-icon.swift <output-dir> [icon|logo]
let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let cyan: UInt32 = 0x00F0FF, violet: UInt32 = 0x8A2BE2, magenta: UInt32 = 0xFF007F, base: UInt32 = 0x0A0A0E

enum Style { case color, mono }

func lerp(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> CGColor {
    func c(_ v: UInt32, _ s: UInt32) -> CGFloat { CGFloat((v >> s) & 0xFF) / 255 }
    return CGColor(srgbRed: c(a, 16) + (c(b, 16) - c(a, 16)) * t, green: c(a, 8) + (c(b, 8) - c(a, 8)) * t, blue: c(a, 0) + (c(b, 0) - c(a, 0)) * t, alpha: 1)
}

/// Cyan → violet → magenta → cyan around the circle.
func spectrum(_ t: CGFloat) -> CGColor {
    let t = t.truncatingRemainder(dividingBy: 1)
    if t < 1.0 / 3 { return lerp(cyan, violet, t * 3) }
    if t < 2.0 / 3 { return lerp(violet, magenta, (t - 1.0 / 3) * 3) }
    return lerp(magenta, cyan, (t - 2.0 / 3) * 3)
}

/// Deterministic noise so every render of the brush is identical.
struct SeededRandom {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 33) / CGFloat(1 << 31)
    }
}

/// A tapered ensō-style brush stroke that sweeps once around the mark near the icon edge and closes
/// the circle, its tail tucking just inside its head. Shades from #3B82F6 at the start to #64748B at the end.
func drawBrush(_ ctx: CGContext, center: CGPoint, scale s: CGFloat, style: Style) {
    let startBlue: UInt32 = 0x3B82F6, endSlate: UInt32 = 0x64748B
    let startAngle = CGFloat.pi * 0.62
    let sweep = 2 * CGFloat.pi * 1.06
    let steps = 900
    var random = SeededRandom(state: 7)
    let bristles = 22

    func point(_ t: CGFloat) -> (CGPoint, CGFloat, CGFloat) {
        let angle = startAngle - sweep * t
        // A gentle inward spiral so the tail passes just inside the head, plus a slight hand-drawn waver.
        let radius = (430 - 22 * t + 4 * sin(t * 2 * .pi * 1.5)) * s
        // Pressed hard early, lifting off into a fine point at the end.
        let press = pow(sin(CGFloat.pi * min(max(t, 0), 1)), 0.5) * (1 - 0.35 * t)
        let width = (1.5 + 44 * press) * s
        return (CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius), angle, width)
    }

    ctx.saveGState()
    ctx.setLineCap(.round)
    if style == .color { ctx.setShadow(offset: .zero, blur: 16 * s, color: rgb(startBlue, 0.35)) }
    for bristle in 0..<bristles {
        let lane = (CGFloat(bristle) + 0.5) / CGFloat(bristles) - 0.5
        let baseAlpha = 0.45 + 0.55 * random.next()
        let fray = abs(lane) * 2
        let tStart = fray * 0.04 * random.next()
        let tEnd = 1 - fray * 0.12 * random.next()
        let thickness = (2.4 + 2.2 * random.next()) * s
        let flicker = 18 + 40 * random.next(), phase = random.next() * 6.28
        var previous: CGPoint?
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            guard t >= tStart, t <= tEnd else { previous = nil; continue }
            // Dry brush: toward the end, bristles skip, leaving streaks.
            let dryness = max(0, (t - 0.62) / 0.38)
            if random.next() < dryness * dryness * (0.25 + 0.6 * fray) { previous = nil; continue }
            let (base, angle, width) = point(t)
            let offset = lane * width
            let p = CGPoint(x: base.x + cos(angle) * offset, y: base.y + sin(angle) * offset)
            if let previous {
                let alpha = baseAlpha * (0.8 + 0.2 * sin(t * flicker + phase)) * (1 - 0.35 * dryness)
                let color = style == .color ? lerp(startBlue, endSlate, t).copy(alpha: alpha)! : CGColor(gray: 1, alpha: alpha)
                ctx.setStrokeColor(color)
                ctx.setLineWidth(thickness)
                ctx.move(to: previous)
                ctx.addLine(to: p)
                ctx.strokePath()
            }
            previous = p
        }
    }
    ctx.restoreGState()
}

func drawMark(_ ctx: CGContext, center: CGPoint, scale s: CGFloat, style: Style) {
    drawBrush(ctx, center: center, scale: s, style: style)

    // Outer dotted ring, like the Live Photo symbol.
    let dots = 40
    ctx.saveGState()
    if style == .color { ctx.setShadow(offset: .zero, blur: 26 * s, color: rgb(cyan, 0.55)) }
    for i in 0..<dots {
        let t = CGFloat(i) / CGFloat(dots)
        let angle = t * 2 * .pi - .pi / 2
        let p = CGPoint(x: center.x + cos(angle) * 340 * s, y: center.y + sin(angle) * 340 * s)
        ctx.setFillColor(style == .color ? spectrum(t) : CGColor(gray: 1, alpha: 0.85))
        let r = 12 * s
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    }
    ctx.restoreGState()

    // Solid middle ring with a conic neon gradient and glow.
    let ringRadius = 238 * s, ringWidth = 40 * s
    let ring = CGMutablePath()
    ring.addEllipse(in: CGRect(x: center.x - ringRadius - ringWidth / 2, y: center.y - ringRadius - ringWidth / 2, width: 2 * (ringRadius + ringWidth / 2), height: 2 * (ringRadius + ringWidth / 2)))
    ring.addEllipse(in: CGRect(x: center.x - ringRadius + ringWidth / 2, y: center.y - ringRadius + ringWidth / 2, width: 2 * (ringRadius - ringWidth / 2), height: 2 * (ringRadius - ringWidth / 2)))

    if style == .color {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 70 * s, color: rgb(violet, 0.9))
        ctx.addPath(ring)
        ctx.setFillColor(rgb(violet, 0.9))
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(ring)
    ctx.clip(using: .evenOdd)
    if style == .color {
        let segments = 360
        ctx.setLineWidth(ringWidth + 4 * s)
        for i in 0..<segments {
            let t = CGFloat(i) / CGFloat(segments)
            let start = t * 2 * .pi - .pi / 2
            ctx.setStrokeColor(spectrum(t))
            ctx.addArc(center: center, radius: ringRadius, startAngle: start, endAngle: start + 2 * .pi / CGFloat(segments) * 1.6, clockwise: false)
            ctx.strokePath()
        }
    } else {
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
    }
    ctx.restoreGState()

    // Glowing core.
    let core = 104 * s
    ctx.saveGState()
    if style == .color { ctx.setShadow(offset: .zero, blur: 80 * s, color: rgb(cyan, 1)) }
    ctx.addEllipse(in: CGRect(x: center.x - core, y: center.y - core, width: 2 * core, height: 2 * core))
    ctx.clip()
    let coreColors = style == .color ? [CGColor(gray: 1, alpha: 1), rgb(cyan)] : [CGColor(gray: 1, alpha: 1), CGColor(gray: 0.8, alpha: 1)]
    let coreGradient = CGGradient(colorsSpace: space, colors: coreColors as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(coreGradient, startCenter: CGPoint(x: center.x - core * 0.3, y: center.y + core * 0.35), startRadius: 0, endCenter: center, endRadius: core, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
}

func render(size: Int, background: Bool, style: Style, name: String) throws {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(size) / 1024
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    if background {
        ctx.setFillColor(rgb(base))
        ctx.fill(full)
        for (hex, alpha, x, y, radius) in [(cyan, 0.30, 180.0, 860.0, 720.0), (violet, 0.42, 900.0, 140.0, 760.0), (magenta, 0.22, 120.0, 90.0, 520.0)] as [(UInt32, CGFloat, CGFloat, CGFloat, CGFloat)] {
            let g = CGGradient(colorsSpace: space, colors: [rgb(hex, alpha), rgb(hex, 0)] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: x * s, y: y * s), startRadius: 0, endCenter: CGPoint(x: x * s, y: y * s), endRadius: radius * s, options: [])
        }
    }
    drawMark(ctx, center: CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2), scale: s * (background ? 1 : 1.0), style: style)
    if background {
        // Soft glass sheen across the top.
        let sheen = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.07), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: 0, y: CGFloat(size) * 0.55), options: [])
    }
    let image = ctx.makeImage()!
    let url = outputDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print(name)
}

// MARK: - Logo (flat)

import CoreText

let brandBlue: UInt32 = 0x3B82F6, brandSlate: UInt32 = 0x64748B, ink: UInt32 = 0x0F172A, night: UInt32 = 0x0B1120

/// A four-point glint: the "glitter" in the brand. Solid fill, no effects.
func drawSparkle(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat, color: CGColor) {
    let waist = r * 0.14
    let path = CGMutablePath()
    path.move(to: CGPoint(x: c.x, y: c.y + r))
    path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + waist, y: c.y + waist))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + waist, y: c.y - waist))
    path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - waist, y: c.y - waist))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - waist, y: c.y + waist))
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

/// A solid tapered ensō: pressed thick at the start, lifting to a point as it closes the circle.
func ensoPath(center: CGPoint, scale s: CGFloat) -> CGPath {
    let startAngle = CGFloat.pi * 0.62
    let sweep = 2 * CGFloat.pi * 0.965
    let steps = 360
    var outer: [CGPoint] = [], inner: [CGPoint] = []
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps)
        let angle = startAngle - sweep * t
        let radius = (400 - 10 * t) * s
        let press = pow(sin(CGFloat.pi * min(max(t * 0.94 + 0.06, 0), 1)), 0.55) * (1 - 0.45 * t)
        let half = (4 + 58 * press) * s / 2
        outer.append(CGPoint(x: center.x + cos(angle) * (radius + half), y: center.y + sin(angle) * (radius + half)))
        inner.append(CGPoint(x: center.x + cos(angle) * (radius - half), y: center.y + sin(angle) * (radius - half)))
    }
    let path = CGMutablePath()
    path.addLines(between: outer + inner.reversed())
    path.closeSubpath()
    return path
}

/// The rounded tip where the brush first touches down.
func ensoHead(center: CGPoint, scale s: CGFloat) -> CGRect {
    let angle = CGFloat.pi * 0.62
    let radius = 400 * s
    let half = (4 + 58 * pow(sin(CGFloat.pi * 0.06), 0.55)) * s / 2
    let c = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    return CGRect(x: c.x - half, y: c.y - half, width: 2 * half, height: 2 * half)
}

/// Ensō, a dotted Live Photo ring, and glints, all in flat brand colors.
func drawLogoMark(_ ctx: CGContext, center: CGPoint, scale s: CGFloat, onDark: Bool) {
    let blue = rgb(brandBlue), slate = rgb(brandSlate)
    ctx.addPath(ensoPath(center: center, scale: s))
    ctx.setFillColor(blue)
    ctx.fillPath()
    ctx.fillEllipse(in: ensoHead(center: center, scale: s))

    let dots = 28
    ctx.setFillColor(slate)
    for i in 0..<dots {
        let angle = CGFloat(i) / CGFloat(dots) * 2 * .pi
        let p = CGPoint(x: center.x + cos(angle) * 292 * s, y: center.y + sin(angle) * 292 * s)
        let r = 9 * s
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    }

    drawSparkle(ctx, at: CGPoint(x: center.x, y: center.y), radius: 200 * s, color: onDark ? CGColor(gray: 1, alpha: 1) : rgb(ink))
    drawSparkle(ctx, at: CGPoint(x: center.x + 150 * s, y: center.y + 150 * s), radius: 62 * s, color: blue)
    drawSparkle(ctx, at: CGPoint(x: center.x - 138 * s, y: center.y - 150 * s), radius: 38 * s, color: slate)
}

func registerInter() {
    let fonts = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        .appendingPathComponent("../LiveWall/Resources/Fonts/Inter-Bold.ttf").standardizedFileURL
    CTFontManagerRegisterFontsForURL(fonts as CFURL, .process, nil)
}

func textLine(_ string: String, font: CTFont) -> (CGPath, CTLine) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.init(kCTFontAttributeName as String): font]))
    let path = CGMutablePath()
    for run in (CTLineGetGlyphRuns(line) as! [CTRun]) {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for (glyph, position) in zip(glyphs, positions) {
            if let glyphPath = CTFontCreatePathForGlyph(font, glyph, nil) {
                path.addPath(glyphPath, transform: CGAffineTransform(translationX: position.x, y: position.y))
            }
        }
    }
    return (path, line)
}

enum Theme { case dark, light }
enum Layout { case horizontal, stacked }

let wordmarkSize: CGFloat = 320
let wordGap = wordmarkSize * 0.24

func wordmarkWidth() -> CGFloat {
    let font = CTFontCreateWithName("Inter-Bold" as CFString, wordmarkSize, nil)
    return CTLineGetTypographicBounds(textLine("Gl\u{0131}tter", font: font).1, nil, nil, nil) + wordGap
        + CTLineGetTypographicBounds(textLine("Live", font: font).1, nil, nil, nil)
}

/// "Glıtter Live": the i's dot is a glint, and "Live" is in brand blue.
func drawWordmark(_ ctx: CGContext, origin: CGPoint, theme: Theme) {
    let font = CTFontCreateWithName("Inter-Bold" as CFString, wordmarkSize, nil)
    let (glitterPath, glitterLine) = textLine("Gl\u{0131}tter", font: font)
    let (livePath, _) = textLine("Live", font: font)
    let glitterWidth = CTLineGetTypographicBounds(glitterLine, nil, nil, nil)

    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.addPath(glitterPath)
    ctx.setFillColor(theme == .dark ? CGColor(gray: 1, alpha: 1) : rgb(ink))
    ctx.fillPath()
    ctx.saveGState()
    ctx.translateBy(x: glitterWidth + wordGap, y: 0)
    ctx.addPath(livePath)
    ctx.setFillColor(rgb(brandBlue))
    ctx.fillPath()
    ctx.restoreGState()
    let iStart = CTLineGetOffsetForStringIndex(glitterLine, 2, nil)
    let iEnd = CTLineGetOffsetForStringIndex(glitterLine, 3, nil)
    drawSparkle(ctx, at: CGPoint(x: (iStart + iEnd) / 2, y: CTFontGetXHeight(font) + wordmarkSize * 0.2), radius: wordmarkSize * 0.15, color: rgb(brandBlue))
    ctx.restoreGState()
}

func writePNG(_ ctx: CGContext, _ name: String) {
    let dest = CGImageDestinationCreateWithURL(outputDir.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print(name)
}

func renderLogo(layout: Layout, theme: Theme, background: Bool, name: String) {
    let font = CTFontCreateWithName("Inter-Bold" as CFString, wordmarkSize, nil)
    let capHeight = CTFontGetCapHeight(font)
    let textWidth = wordmarkWidth()
    let markSize: CGFloat = 760, padding: CGFloat = 120

    let width: Int, height: Int, markCenter: CGPoint, textOrigin: CGPoint
    switch layout {
    case .horizontal:
        width = Int(padding * 2 + markSize + 70 + textWidth)
        height = Int(markSize + padding * 2)
        markCenter = CGPoint(x: padding + markSize / 2, y: CGFloat(height) / 2)
        textOrigin = CGPoint(x: padding + markSize + 70, y: CGFloat(height) / 2 - capHeight / 2)
    case .stacked:
        width = Int(max(markSize, textWidth) + padding * 2)
        height = Int(padding * 2 + markSize + 80 + capHeight + 30)
        markCenter = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) - padding - markSize / 2)
        textOrigin = CGPoint(x: (CGFloat(width) - textWidth) / 2, y: padding + 20)
    }
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if background {
        ctx.setFillColor(theme == .dark ? rgb(night) : CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    drawLogoMark(ctx, center: markCenter, scale: markSize / 1024, onDark: theme == .dark)
    drawWordmark(ctx, origin: textOrigin, theme: theme)
    writePNG(ctx, name)
}

func renderMark(theme: Theme, background: Bool, name: String) {
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if background {
        ctx.setFillColor(theme == .dark ? rgb(night) : CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    }
    drawLogoMark(ctx, center: CGPoint(x: 512, y: 512), scale: 1, onDark: theme == .dark)
    writePNG(ctx, name)
}

// MARK: - Entry point

let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "icon"
if mode == "logo" {
    registerInter()
    renderLogo(layout: .horizontal, theme: .light, background: true, name: "GlitterLive-Logo-Horizontal-Light.png")
    renderLogo(layout: .horizontal, theme: .dark, background: true, name: "GlitterLive-Logo-Horizontal-Dark.png")
    renderLogo(layout: .horizontal, theme: .light, background: false, name: "GlitterLive-Logo-Horizontal-Light-Transparent.png")
    renderLogo(layout: .horizontal, theme: .dark, background: false, name: "GlitterLive-Logo-Horizontal-Dark-Transparent.png")
    renderLogo(layout: .stacked, theme: .light, background: true, name: "GlitterLive-Logo-Stacked-Light.png")
    renderLogo(layout: .stacked, theme: .dark, background: true, name: "GlitterLive-Logo-Stacked-Dark.png")
    renderMark(theme: .light, background: true, name: "GlitterLive-Mark-Light.png")
    renderMark(theme: .dark, background: true, name: "GlitterLive-Mark-Dark.png")
} else {
    try render(size: 1024, background: true, style: .color, name: "AppIcon.png")
    try render(size: 1024, background: false, style: .color, name: "AppIcon-Dark.png")
    try render(size: 1024, background: false, style: .mono, name: "AppIcon-Tinted.png")
    for (scale, px) in [(1, 150), (2, 300), (3, 450)] {
        try render(size: px, background: false, style: .color, name: "LaunchLogo@\(scale)x.png")
    }
}
