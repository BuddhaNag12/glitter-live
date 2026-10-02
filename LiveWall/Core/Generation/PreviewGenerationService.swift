import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Paints soft light in the style's colors and animates any image with a slow push-in. Stands in for the AI
/// server offline and in screenshot runs (`-previewGenerator`), and is the motion fallback when the depth model is missing.
nonisolated struct PreviewGenerationService: GenerationService {
    private static let size = (width: 720, height: 1560)

    @concurrent
    func makeImage(for request: GenerationRequest) async throws -> URL {
        // Long enough to see the progress steps, as a real generation will take a few seconds.
        try await Task.sleep(for: .seconds(1.5))
        let (width, height) = Self.size
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw GenerationError.imageFailed }

        context.setFillColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Seeded by the prompt, so the same prompt paints the same picture.
        var state = request.fullPrompt.utf8.reduce(UInt64(0xCBF29CE484222325)) { ($0 ^ UInt64($1)) &* 0x100000001B3 }
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 11) / CGFloat(1 << 53)
        }
        for (index, hex) in (request.style.palette + request.style.palette).enumerated() {
            let center = CGPoint(x: CGFloat(width) * next(), y: CGFloat(height) * next())
            let radius = CGFloat(width) * (0.45 + 0.4 * next())
            let color = Self.color(hex, alpha: index < 3 ? 0.85 : 0.5)
            let gradient = CGGradient(colorsSpace: colorSpace, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }
        for _ in 0..<140 {
            let speck = CGRect(x: CGFloat(width) * next(), y: CGFloat(height) * next(), width: 1 + next() * 3, height: 1 + next() * 3)
            context.setFillColor(CGColor(gray: 1, alpha: 0.25 + next() * 0.6))
            context.fillEllipse(in: speck)
        }

        guard let image = context.makeImage() else { throw GenerationError.imageFailed }
        let url = URL.temporaryDirectory.appending(path: "generated-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw GenerationError.imageFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GenerationError.imageFailed }
        return url
    }

    @concurrent
    func animate(imageAt imageURL: URL, for request: GenerationRequest) async throws -> URL {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw GenerationError.videoFailed }
        let (width, height) = Self.size
        let fps: Int32 = 30, frameCount = 90
        let url = URL.temporaryDirectory.appending(path: "generated-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
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

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let pool = adaptor.pixelBufferPool else { throw GenerationError.videoFailed }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw GenerationError.videoFailed }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) {
                let eased = 0.5 - cos(Double(frame) / Double(frameCount - 1) * .pi) / 2
                // Fills the frame without stretching, so a square AI image is cropped to the sides rather than squashed.
                let fill = max(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
                let scale = fill * (1 + 0.08 * eased)
                let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                let origin = CGPoint(x: (CGFloat(width) - drawn.width) / 2, y: (CGFloat(height) - drawn.height) / 2 - 24 * eased)
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(origin: origin, size: drawn))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
        return url
    }

    private static func color(_ hex: UInt32, alpha: CGFloat) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
