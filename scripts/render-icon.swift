import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Usage: swift scripts/render-icon.swift <output-dir> [icon|logo|appbar|svg|store <captures-dir>]
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
func sparklePath(at c: CGPoint, radius r: CGFloat) -> CGPath {
    let waist = r * 0.14
    let path = CGMutablePath()
    path.move(to: CGPoint(x: c.x, y: c.y + r))
    path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + waist, y: c.y + waist))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + waist, y: c.y - waist))
    path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - waist, y: c.y - waist))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - waist, y: c.y + waist))
    path.closeSubpath()
    return path
}

func drawSparkle(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat, color: CGColor) {
    ctx.addPath(sparklePath(at: c, radius: r))
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

// MARK: - Layered SVG

/// Vector logo with every part on its own named layer, for motion tools like Jitter.
enum SVG {
    static func pathData(_ path: CGPath, height: CGFloat) -> String {
        var d = ""
        func p(_ point: CGPoint) -> String { String(format: "%.2f %.2f", point.x, height - point.y) }
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: d += "M\(p(e.points[0]))"
            case .addLineToPoint: d += "L\(p(e.points[0]))"
            case .addQuadCurveToPoint: d += "Q\(p(e.points[0])) \(p(e.points[1]))"
            case .addCurveToPoint: d += "C\(p(e.points[0])) \(p(e.points[1])) \(p(e.points[2]))"
            case .closeSubpath: d += "Z"
            @unknown default: break
            }
        }
        return d
    }

    static func hex(_ value: UInt32) -> String { String(format: "#%06X", value) }

    static func circle(_ rect: CGRect, height: CGFloat) -> String {
        String(format: "cx=\"%.2f\" cy=\"%.2f\" r=\"%.2f\"", rect.midX, height - rect.midY, rect.width / 2)
    }

    static func mark(center: CGPoint, scale s: CGFloat, theme: Theme, height h: CGFloat) -> String {
        let starColor = theme == .dark ? "#FFFFFF" : hex(ink)
        var out = "<g id=\"mark\">\n"
        out += "  <g id=\"enso\" fill=\"\(hex(brandBlue))\">\n"
        out += "    <path id=\"enso-stroke\" d=\"\(pathData(ensoPath(center: center, scale: s), height: h))\"/>\n"
        out += "    <circle id=\"enso-head\" \(circle(ensoHead(center: center, scale: s), height: h))/>\n"
        out += "  </g>\n"
        out += "  <g id=\"dots\" fill=\"\(hex(brandSlate))\">\n"
        for i in 0..<28 {
            // Numbered clockwise from the ensō's head, so a stagger follows the brush.
            let angle = CGFloat.pi * 0.62 - CGFloat(i) / 28 * 2 * .pi
            let point = CGPoint(x: center.x + cos(angle) * 292 * s, y: center.y + sin(angle) * 292 * s)
            let r = 9 * s
            out += "    <circle id=\"dot-\(String(format: "%02d", i + 1))\" \(circle(CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r), height: h))/>\n"
        }
        out += "  </g>\n"
        out += "  <path id=\"star\" fill=\"\(starColor)\" d=\"\(pathData(sparklePath(at: center, radius: 200 * s), height: h))\"/>\n"
        out += "  <path id=\"sparkle-blue\" fill=\"\(hex(brandBlue))\" d=\"\(pathData(sparklePath(at: CGPoint(x: center.x + 150 * s, y: center.y + 150 * s), radius: 62 * s), height: h))\"/>\n"
        out += "  <path id=\"sparkle-slate\" fill=\"\(hex(brandSlate))\" d=\"\(pathData(sparklePath(at: CGPoint(x: center.x - 138 * s, y: center.y - 150 * s), radius: 38 * s), height: h))\"/>\n"
        return out + "</g>\n"
    }

    /// One path per letter, so a motion tool can stagger them.
    static func word(_ string: String, id: String, font: CTFont, origin: CGPoint, color: String, height h: CGFloat) -> String {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.init(kCTFontAttributeName as String): font]))
        var out = "  <g id=\"\(id)\" fill=\"\(color)\">\n"
        var index = 0
        for run in (CTLineGetGlyphRuns(line) as! [CTRun]) {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let characters = Array(string)
            for (glyph, position) in zip(glyphs, positions) {
                guard let glyphPath = CTFontCreatePathForGlyph(font, glyph, nil) else { index += 1; continue }
                var move = CGAffineTransform(translationX: origin.x + position.x, y: origin.y + position.y)
                let placed = glyphPath.copy(using: &move)!
                let letter = characters[index] == "\u{0131}" ? "i" : String(characters[index])
                out += "    <path id=\"\(id)-\(index + 1)-\(letter)\" d=\"\(pathData(placed, height: h))\"/>\n"
                index += 1
            }
        }
        return out + "  </g>\n"
    }

    static func wordmark(origin: CGPoint, theme: Theme, height h: CGFloat) -> String {
        let font = CTFontCreateWithName("Inter-Bold" as CFString, wordmarkSize, nil)
        let glitterLine = textLine("Gl\u{0131}tter", font: font).1
        let glitterWidth = CTLineGetTypographicBounds(glitterLine, nil, nil, nil)
        let iStart = CTLineGetOffsetForStringIndex(glitterLine, 2, nil)
        let iEnd = CTLineGetOffsetForStringIndex(glitterLine, 3, nil)
        let glint = sparklePath(at: CGPoint(x: origin.x + (iStart + iEnd) / 2, y: origin.y + CTFontGetXHeight(font) + wordmarkSize * 0.2), radius: wordmarkSize * 0.15)
        var out = "<g id=\"wordmark\">\n"
        out += word("Gl\u{0131}tter", id: "glitter", font: font, origin: origin, color: theme == .dark ? "#FFFFFF" : hex(ink), height: h)
        out += word("Live", id: "live", font: font, origin: CGPoint(x: origin.x + glitterWidth + wordGap, y: origin.y), color: hex(brandBlue), height: h)
        out += "  <path id=\"i-sparkle\" fill=\"\(hex(brandBlue))\" d=\"\(pathData(glint, height: h))\"/>\n"
        return out + "</g>\n"
    }

    static func write(_ body: String, width: CGFloat, height: CGFloat, name: String) {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(width))" height="\(Int(height))" viewBox="0 0 \(Int(width)) \(Int(height))">
        \(body)</svg>

        """
        try! svg.write(to: outputDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        print(name)
    }

    /// Same geometry as the horizontal PNG lockup, on a transparent canvas.
    static func renderHorizontal(theme: Theme, name: String) {
        let font = CTFontCreateWithName("Inter-Bold" as CFString, wordmarkSize, nil)
        let markSize: CGFloat = 760, padding: CGFloat = 120
        let width = padding * 2 + markSize + 70 + wordmarkWidth(), height = markSize + padding * 2
        let body = mark(center: CGPoint(x: padding + markSize / 2, y: height / 2), scale: markSize / 1024, theme: theme, height: height)
            + wordmark(origin: CGPoint(x: padding + markSize + 70, y: height / 2 - CTFontGetCapHeight(font) / 2), theme: theme, height: height)
        write(body, width: width, height: height, name: name)
    }

    static func renderMark(theme: Theme, name: String) {
        write(mark(center: CGPoint(x: 512, y: 512), scale: 1, theme: theme, height: 1024), width: 1024, height: 1024, name: name)
    }
}

// MARK: - Entry point

// MARK: - App Store screenshots, product page header and search results

/// Opaque, so App Store Connect accepts the PNGs (it rejects any alpha channel).
func storeContext(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}

/// The app's night sky: brand blue and silver glows with a few glints.
func drawStoreBackground(_ ctx: CGContext, _ size: CGSize) {
    ctx.setFillColor(rgb(night))
    ctx.fill(CGRect(origin: .zero, size: size))
    let reach = max(size.width, size.height)
    for (hex, alpha, x, y, radius) in [(brandBlue, 0.45, 0.12, 0.92, 0.75), (0x94A3B8, 0.18, 0.92, 0.2, 0.7)] as [(UInt32, CGFloat, CGFloat, CGFloat, CGFloat)] {
        let glow = CGGradient(colorsSpace: space, colors: [rgb(hex, alpha), rgb(hex, 0)] as CFArray, locations: [0, 1])!
        let center = CGPoint(x: x * size.width, y: y * size.height)
        ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius * reach, options: [])
    }
    for (x, y, r, alpha) in [(0.08, 0.6, 0.012, 0.5), (0.9, 0.78, 0.016, 0.6), (0.82, 0.45, 0.008, 0.4), (0.035, 0.1, 0.01, 0.35)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        drawSparkle(ctx, at: CGPoint(x: x * size.width, y: y * size.height), radius: r * reach, color: CGColor(gray: 1, alpha: alpha))
    }
}

/// A real app screen in a rounded slate frame. Drawn, not Apple's device art, so there's no rights question.
func drawPhone(_ ctx: CGContext, _ image: CGImage, center: CGPoint, width: CGFloat, angle: CGFloat = 0) {
    let height = width * CGFloat(image.height) / CGFloat(image.width)
    let bezel = width * 0.022, radius = width * 0.14
    let outer = CGRect(x: -width / 2 - bezel, y: -height / 2 - bezel, width: width + bezel * 2, height: height + bezel * 2)
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle)
    ctx.setShadow(offset: CGSize(width: 0, height: -width * 0.03), blur: width * 0.12, color: CGColor(gray: 0, alpha: 0.6))
    ctx.addPath(CGPath(roundedRect: outer, cornerWidth: radius + bezel, cornerHeight: radius + bezel, transform: nil))
    ctx.setFillColor(rgb(0x1E293B))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0)
    ctx.addPath(CGPath(roundedRect: outer.insetBy(dx: bezel * 0.15, dy: bezel * 0.15), cornerWidth: radius + bezel, cornerHeight: radius + bezel, transform: nil))
    ctx.setStrokeColor(rgb(0x475569))
    ctx.setLineWidth(bezel * 0.3)
    ctx.strokePath()
    let screen = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(image, in: screen)
    ctx.restoreGState()
}

/// Wrapped Inter Bold, top-aligned in `rect`.
func drawText(_ ctx: CGContext, _ text: String, in rect: CGRect, size: CGFloat, color: CGColor, centered: Bool = true) {
    var alignment: CTTextAlignment = centered ? .center : .left
    var spacing = size * 0.08
    let style = withUnsafePointer(to: &alignment) { a in
        withUnsafePointer(to: &spacing) { s in
            CTParagraphStyleCreate([
                CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: a),
                CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: s),
            ], 2)
        }
    }
    let string = NSAttributedString(string: text, attributes: [
        .init(kCTFontAttributeName as String): CTFontCreateWithName("Inter-Bold" as CFString, size, nil),
        .init(kCTForegroundColorAttributeName as String): color,
        .init(kCTParagraphStyleAttributeName as String): style,
    ])
    let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(string), CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
    CTFrameDraw(frame, ctx)
}

func drawLockup(_ ctx: CGContext, origin: CGPoint, height: CGFloat) {
    let scale = height / wordmarkSize
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.scaleBy(x: scale, y: scale)
    drawLogoMark(ctx, center: CGPoint(x: wordmarkSize * 0.55, y: wordmarkSize * 0.36), scale: wordmarkSize * 1.1 / 1024, onDark: true)
    drawWordmark(ctx, origin: CGPoint(x: wordmarkSize * 1.3, y: 0), theme: .dark)
    ctx.restoreGState()
}

func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Can't read \(url.path)")
    }
    return image
}

/// Headline on top, the screen below, running off the bottom edge. Laid out on the 6.9" canvas and scaled.
func renderStoreShot(_ capture: CGImage, caption: String, width: Int, height: Int, name: String) {
    let ctx = storeContext(width, height)
    let size = CGSize(width: width, height: height)
    let s = size.width / 1320
    drawStoreBackground(ctx, size)
    drawText(ctx, caption, in: CGRect(x: 110 * s, y: size.height - 600 * s, width: size.width - 220 * s, height: 440 * s), size: 104 * s, color: CGColor(gray: 1, alpha: 1))
    let phoneWidth = 1000 * s
    let phoneHeight = phoneWidth * CGFloat(capture.height) / CGFloat(capture.width)
    drawPhone(ctx, capture, center: CGPoint(x: size.width / 2, y: size.height - 640 * s - phoneHeight / 2), width: phoneWidth)
    writePNG(ctx, name)
}

let tagline = "Turn any video into a live wallpaper"

/// 3:2. The brand and line on the left, two screens on the right.
func renderSearch(_ screens: [CGImage], name: String) {
    let size = CGSize(width: 1920, height: 1280)
    let ctx = storeContext(Int(size.width), Int(size.height))
    drawStoreBackground(ctx, size)
    drawLockup(ctx, origin: CGPoint(x: 110, y: 820), height: 96)
    drawText(ctx, tagline, in: CGRect(x: 110, y: 300, width: 760, height: 460), size: 88, color: CGColor(gray: 1, alpha: 1), centered: false)
    drawPhone(ctx, screens[1], center: CGPoint(x: 1640, y: 560), width: 470, angle: -0.06)
    drawPhone(ctx, screens[0], center: CGPoint(x: 1230, y: 600), width: 500, angle: 0.03)
    writePNG(ctx, name)
}

// MARK: - Product page header

/// An image scaled to fill `rect`, cropped to it, with rounded corners.
func drawFill(_ ctx: CGContext, _ image: CGImage, in rect: CGRect, radius: CGFloat) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
    let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    ctx.restoreGState()
}

/// 21:9. A tilted wall of real Explore wallpapers, with the brand centred on a dark band. Centred on purpose:
/// the App Store crops the header per device and only the middle survives everywhere.
func renderHeader(_ walls: [CGImage], name: String) {
    let size = CGSize(width: 3840, height: 1646)
    let ctx = storeContext(Int(size.width), Int(size.height))
    ctx.setFillColor(rgb(night))
    ctx.fill(CGRect(origin: .zero, size: size))
    ctx.saveGState()
    ctx.translateBy(x: size.width / 2, y: size.height / 2)
    ctx.rotate(by: -0.2)
    let tileW: CGFloat = 300, tileH: CGFloat = 650, gap: CGFloat = 36
    var index = 0
    for column in -8...8 {
        let offset = column.isMultiple(of: 2) ? 0 : tileH / 2
        for row in -2...2 {
            let rect = CGRect(x: CGFloat(column) * (tileW + gap) - tileW / 2, y: CGFloat(row) * (tileH + gap) - tileH / 2 + offset, width: tileW, height: tileH)
            drawFill(ctx, walls[index % walls.count], in: rect, radius: 40)
            index += 1
        }
    }
    ctx.restoreGState()
    // Darken towards the middle so the brand reads.
    let band = CGGradient(colorsSpace: space, colors: [rgb(night, 0), rgb(night, 0.86), rgb(night, 0.86), rgb(night, 0)] as CFArray, locations: [0, 0.3, 0.7, 1])!
    ctx.drawLinearGradient(band, start: CGPoint(x: 0, y: 350), end: CGPoint(x: 0, y: 1296), options: [])
    let side = CGGradient(colorsSpace: space, colors: [rgb(night, 0.55), rgb(night, 0), rgb(night, 0), rgb(night, 0.55)] as CFArray, locations: [0, 0.25, 0.75, 1])!
    ctx.drawLinearGradient(side, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
    drawLockup(ctx, origin: CGPoint(x: 1920 - 420, y: 880), height: 130)
    drawText(ctx, "Bring your Lock Screen to life", in: CGRect(x: 960, y: 560, width: 1920, height: 200), size: 100, color: CGColor(gray: 1, alpha: 1))
    writePNG(ctx, name)
}

// MARK: - Original abstract wallpapers

/// A small seeded generator, so the same seed always draws the same wallpaper.
struct Seeded {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 33) / CGFloat(1 << 31)
    }
    mutating func between(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}

/// Soft colour fields with flowing ribbons on a deep base: original artwork, free of any licence.
func renderAbstract(palette: [UInt32], seed: UInt64, name: String) {
    let size = CGSize(width: 1179, height: 2556)
    let ctx = storeContext(Int(size.width), Int(size.height))
    var random = Seeded(state: seed)
    ctx.setFillColor(rgb(palette[2]))
    ctx.fill(CGRect(origin: .zero, size: size))
    // Big soft blobs of the two accents.
    for index in 0..<5 {
        let hex = palette[index % 2]
        let center = CGPoint(x: random.between(-0.1, 1.1) * size.width, y: random.between(0, 1) * size.height)
        let radius = random.between(0.45, 0.9) * size.width
        let glow = CGGradient(colorsSpace: space, colors: [rgb(hex, random.between(0.55, 0.85)), rgb(hex, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
    // Flowing ribbons: wide waves, each a gradient between the accents.
    for _ in 0..<4 {
        let baseY = random.between(0.1, 0.9) * size.height
        let amplitude = random.between(0.08, 0.2) * size.height
        let thickness = random.between(0.05, 0.14) * size.height
        let phase = random.between(0, .pi * 2)
        let path = CGMutablePath()
        let steps = 60
        func y(_ t: CGFloat) -> CGFloat { baseY + sin(t * .pi * 1.4 + phase) * amplitude }
        path.move(to: CGPoint(x: -20, y: y(0)))
        for step in 1...steps { let t = CGFloat(step) / CGFloat(steps); path.addLine(to: CGPoint(x: t * (size.width + 40) - 20, y: y(t))) }
        for step in stride(from: steps, through: 0, by: -1) {
            let t = CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: t * (size.width + 40) - 20, y: y(t) + thickness * (0.6 + 0.4 * sin(t * .pi))))
        }
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let ribbon = CGGradient(colorsSpace: space, colors: [rgb(palette[0], 0.75), rgb(palette[1], 0.75)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(ribbon, start: CGPoint(x: 0, y: baseY), end: CGPoint(x: size.width, y: baseY + amplitude), options: [])
        // A soft highlight along the top edge gives the ribbon depth.
        ctx.setBlendMode(.screen)
        let sheen = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.25), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: baseY + amplitude), end: CGPoint(x: 0, y: baseY - amplitude), options: [])
        ctx.restoreGState()
    }
    writePNG(ctx, name)
}

let abstractPalettes: [[UInt32]] = [
    [0xFF6B6B, 0x845EF7, 0x0B1120], [0x22D3EE, 0x3B82F6, 0x0F172A], [0xF59E0B, 0xEF4444, 0x1F1023],
    [0x10B981, 0x06B6D4, 0x062023], [0xEC4899, 0x8B5CF6, 0x140B24], [0xF97316, 0xFACC15, 0x1A1206],
    [0x60A5FA, 0xA78BFA, 0x0B1020], [0x34D399, 0xA3E635, 0x08140D],
]

let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "icon"
if mode == "abstract" {
    // Usage: swift scripts/render-icon.swift <output-dir> abstract (eight original 1179 × 2556 wallpapers)
    for (index, palette) in abstractPalettes.enumerated() {
        renderAbstract(palette: palette, seed: UInt64(index + 1) * 7919, name: String(format: "abstract-%02d.png", index + 1))
    }
} else if mode == "store" {
    // Usage: swift scripts/render-icon.swift <output-dir> store <captures-dir> [<wallpapers-dir>]
    // Captures are the dark screenshots from ScreenshotTests. The header needs a folder of Explore wallpaper images
    // (JPEG or PNG, used in name order), e.g. the original abstract set from the `abstract` mode; without one it's left as it is.
    registerInter()
    let captures = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    func capture(_ name: String) -> CGImage { loadImage(captures.appendingPathComponent("\(name)-dark.png")) }
    let shots = [
        ("explore", "Wallpapers that come alive"),
        ("create-prompt", "Describe a scene. AI makes the wallpaper."),
        ("trim-studio", "Turn any video into a live wallpaper"),
        ("result", "Moves every time you wake your iPhone"),
        ("explore-detail", "Hand-picked live and still wallpapers"),
        ("library-grid", "Everything you make, kept in one place"),
    ]
    for (index, (screen, caption)) in shots.enumerated() {
        let image = capture(screen)
        renderStoreShot(image, caption: caption, width: 1320, height: 2868, name: "iphone-6.9-\(index + 1)-\(screen).png")
        renderStoreShot(image, caption: caption, width: 1206, height: 2622, name: "iphone-6.3-\(index + 1)-\(screen).png")
    }
    if CommandLine.arguments.count > 4 {
        let walls = URL(fileURLWithPath: CommandLine.arguments[4], isDirectory: true)
        let images = ((try? FileManager.default.contentsOfDirectory(atPath: walls.path)) ?? []).filter { $0.hasSuffix(".jpg") || $0.hasSuffix(".png") }.sorted()
        renderHeader(images.map { loadImage(walls.appendingPathComponent($0)) }, name: "header-3840x1646.png")
    }
    renderSearch([capture("trim-studio"), capture("result")], name: "search-1920x1280.png")
} else if mode == "logo" {
    registerInter()
    renderLogo(layout: .horizontal, theme: .light, background: true, name: "GlitterLive-Logo-Horizontal-Light.png")
    renderLogo(layout: .horizontal, theme: .dark, background: true, name: "GlitterLive-Logo-Horizontal-Dark.png")
    renderLogo(layout: .horizontal, theme: .light, background: false, name: "GlitterLive-Logo-Horizontal-Light-Transparent.png")
    renderLogo(layout: .horizontal, theme: .dark, background: false, name: "GlitterLive-Logo-Horizontal-Dark-Transparent.png")
    renderLogo(layout: .stacked, theme: .light, background: true, name: "GlitterLive-Logo-Stacked-Light.png")
    renderLogo(layout: .stacked, theme: .dark, background: true, name: "GlitterLive-Logo-Stacked-Dark.png")
    renderMark(theme: .light, background: true, name: "GlitterLive-Mark-Light.png")
    renderMark(theme: .dark, background: true, name: "GlitterLive-Mark-Dark.png")
} else if mode == "svg" {
    registerInter()
    SVG.renderHorizontal(theme: .light, name: "GlitterLive-Logo-Horizontal-Light.svg")
    SVG.renderHorizontal(theme: .dark, name: "GlitterLive-Logo-Horizontal-Dark.svg")
    SVG.renderMark(theme: .light, name: "GlitterLive-Mark-Light.svg")
    SVG.renderMark(theme: .dark, name: "GlitterLive-Mark-Dark.svg")
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
