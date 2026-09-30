import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Usage: swift scripts/render-icon.swift <output-dir> [icon|logo|appbar]
let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
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
func drawLogoMark(_ ctx: CGContext, center: CGPoint, scale s: CGFloat, onDark: Bool, mono: Bool = false) {
    // The tinted app icon is grayscale; iOS applies the tint.
    let blue = mono ? CGColor(gray: 1, alpha: 1) : rgb(brandBlue)
    let slate = mono ? CGColor(gray: 1, alpha: 0.6) : rgb(brandSlate)
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

    drawSparkle(ctx, at: CGPoint(x: center.x, y: center.y), radius: 200 * s, color: onDark || mono ? CGColor(gray: 1, alpha: 1) : rgb(ink))
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

/// A tight, vector lockup for the in-app header: mark on the left, wordmark on the right.
func renderAppBarLogo(theme: Theme, url: URL) {
    let font = CTFontCreateWithName("Inter-Bold" as CFString, wordmarkSize, nil)
    let capHeight = CTFontGetCapHeight(font)
    let markSize = wordmarkSize * 1.2
    let gap = wordmarkSize * 0.2
    var box = CGRect(x: 0, y: 0, width: markSize + gap + wordmarkWidth(), height: markSize)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    drawLogoMark(ctx, center: CGPoint(x: markSize / 2, y: markSize / 2), scale: markSize / 1024 * 1.08, onDark: theme == .dark)
    drawWordmark(ctx, origin: CGPoint(x: markSize + gap, y: markSize / 2 - capHeight / 2), theme: theme)
    ctx.endPDFPage()
    ctx.closePDF()
    print(url.lastPathComponent)
}

// MARK: - App icon

let obsidian: UInt32 = 0x090C12

/// The flat mark on the Silver Shimmer background: obsidian lit by brand blue and silver slate.
func renderIcon(size: Int, background: Bool, mono: Bool, name: String) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(size) / 1024
    if background {
        ctx.setFillColor(rgb(obsidian))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        for (hex, alpha, x, y, radius) in [(brandBlue, 0.42, 150.0, 900.0, 760.0), (0x94A3B8, 0.30, 900.0, 120.0, 720.0)] as [(UInt32, CGFloat, CGFloat, CGFloat, CGFloat)] {
            let glow = CGGradient(colorsSpace: space, colors: [rgb(hex, alpha), rgb(hex, 0)] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(glow, startCenter: CGPoint(x: x * s, y: y * s), startRadius: 0, endCenter: CGPoint(x: x * s, y: y * s), endRadius: radius * s, options: [])
        }
    }
    drawLogoMark(ctx, center: CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2), scale: s * 0.86, onDark: true, mono: mono)
    writePNG(ctx, name)
}

func renderLaunchLogo(pixels: Int, onDark: Bool, name: String) {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawLogoMark(ctx, center: CGPoint(x: CGFloat(pixels) / 2, y: CGFloat(pixels) / 2), scale: CGFloat(pixels) / 1024, onDark: onDark)
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
} else if mode == "appbar" {
    registerInter()
    renderAppBarLogo(theme: .light, url: outputDir.appendingPathComponent("BrandLogo-Light.pdf"))
    renderAppBarLogo(theme: .dark, url: outputDir.appendingPathComponent("BrandLogo-Dark.pdf"))
} else {
    renderIcon(size: 1024, background: true, mono: false, name: "AppIcon.png")
    renderIcon(size: 1024, background: false, mono: false, name: "AppIcon-Dark.png")
    renderIcon(size: 1024, background: false, mono: true, name: "AppIcon-Tinted.png")
    for (scale, px) in [(1, 150), (2, 300), (3, 450)] {
        renderLaunchLogo(pixels: px, onDark: false, name: "LaunchLogo-Light@\(scale)x.png")
        renderLaunchLogo(pixels: px, onDark: true, name: "LaunchLogo-Dark@\(scale)x.png")
    }
}
