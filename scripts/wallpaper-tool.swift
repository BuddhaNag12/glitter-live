import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Usage:
//   swift scripts/wallpaper-tool.swift probe <video>              → {"duration":…,"width":…,"height":…}
//   swift scripts/wallpaper-tool.swift thumbnail <video> <out.jpg> → a 540 px wide JPEG of the middle frame
//   swift scripts/wallpaper-tool.swift samples <dir>              → original sample loops for testing the catalog

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: wallpaper-tool.swift probe|thumbnail|samples …\n".utf8))
    exit(2)
}

func uprightSize(_ track: AVAssetTrack) async throws -> CGSize {
    let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
    let rect = CGRect(origin: .zero, size: size).applying(transform)
    return CGSize(width: abs(rect.width), height: abs(rect.height))
}

switch arguments[1] {
case "probe":
    let asset = AVURLAsset(url: URL(fileURLWithPath: arguments[2]))
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { exit(1) }
    let size = try await uprightSize(track)
    let duration = try await asset.load(.duration).seconds
    print(#"{"duration":\#(String(format: "%.2f", duration)),"width":\#(Int(size.width)),"height":\#(Int(size.height))}"#)

case "thumbnail":
    let asset = AVURLAsset(url: URL(fileURLWithPath: arguments[2]))
    let duration = try await asset.load(.duration)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 540, height: 1400)
    let image = try await generator.image(at: CMTimeMultiplyByFloat64(duration, multiplier: 0.5)).image
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[3]) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { exit(1) }

case "samples":
    let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for sample in Sample.all {
        let url = directory.appendingPathComponent("\(sample.slug).mp4")
        try await render(sample, to: url)
        print(url.path)
    }

default:
    exit(2)
}

// MARK: - Sample loops

/// A seamless loop of drifting glows with twinkling glitter, in one of the app's palettes.
struct Sample {
    let slug: String
    let base: UInt32
    let glows: [UInt32]
    let sparkle: Bool

    static let all = [
        Sample(slug: "silver-shimmer", base: 0x090C12, glows: [0x3B82F6, 0x94A3B8, 0x1E3A8A], sparkle: true),
        Sample(slug: "blue-lagoon", base: 0x061114, glows: [0x06B6D4, 0x3B82F6, 0x0E7490], sparkle: true),
        Sample(slug: "glacier", base: 0x070D16, glows: [0x38BDF8, 0x2563EB, 0xBAE6FD], sparkle: false),
        Sample(slug: "aqua-spark", base: 0x051012, glows: [0x2DD4BF, 0x22D3EE, 0x3B82F6], sparkle: true),
        Sample(slug: "sapphire-night", base: 0x060816, glows: [0x3B82F6, 0x4F46E5, 0x1E40AF], sparkle: false),
        Sample(slug: "frost-teal", base: 0x0A1113, glows: [0x14B8A6, 0x64748B, 0x0F766E], sparkle: true),
    ]
}

func color(_ hex: UInt32, _ alpha: CGFloat) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ sample: Sample, to url: URL) async throws {
    let width = 1080, height = 1920, fps: Int32 = 30, frameCount = 120
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.hevc,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    var seed: UInt64 = UInt64(truncatingIfNeeded: sample.slug.hashValue) | 1
    func random() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 11) / CGFloat(1 << 53)
    }
    let specks = (0..<140).map { _ in (x: random(), y: random(), size: 1.5 + random() * 3, phase: random() * 2 * .pi, speed: CGFloat(Int(1 + random() * 3))) }

    for frame in 0..<frameCount {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        guard let buffer else { break }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        context.setFillColor(color(sample.base, 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Whole-number frequencies of one full turn make the last frame flow into the first.
        let t = CGFloat(frame) / CGFloat(frameCount) * 2 * .pi
        for (index, glow) in sample.glows.enumerated() {
            let phase = CGFloat(index) * 2.1
            let center = CGPoint(
                x: CGFloat(width) * (0.5 + 0.3 * cos(t + phase)),
                y: CGFloat(height) * (0.5 + 0.28 * sin(t * 2 + phase))
            )
            let gradient = CGGradient(colorsSpace: space, colors: [color(glow, 0.85), color(glow, 0)] as CFArray, locations: [0, 1])!
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(width) * 0.75, options: [])
        }
        if sample.sparkle {
            for speck in specks {
                let alpha = 0.15 + 0.6 * (0.5 + 0.5 * sin(t * speck.speed + speck.phase))
                context.setFillColor(CGColor(gray: 1, alpha: alpha))
                let point = CGPoint(x: speck.x * CGFloat(width), y: speck.y * CGFloat(height))
                context.fillEllipse(in: CGRect(x: point.x - speck.size / 2, y: point.y - speck.size / 2, width: speck.size, height: speck.size))
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
    }
    input.markAsFinished()
    await writer.finishWriting()
    if let error = writer.error { throw error }
}
