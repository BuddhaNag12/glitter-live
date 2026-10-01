#if DEBUG
import AVFoundation
import CoreGraphics

/// Launch arguments that open screens with sample content, for UI screenshot tests.
nonisolated enum DemoLaunch {
    static var opensEditor: Bool { ProcessInfo.processInfo.arguments.contains("-demoVideo") }
    static var opensResult: Bool { ProcessInfo.processInfo.arguments.contains("-demoResult") }
    static var seedsLibrary: Bool { ProcessInfo.processInfo.arguments.contains("-demoLibrary") }
    /// Holds Explore on its loading placeholders for a few seconds before the catalog loads.
    static var holdsLoading: Bool { ProcessInfo.processInfo.arguments.contains("-demoLoading") }
    /// Demo runs use a throwaway store so they never touch the real library.
    static var isDemo: Bool { opensEditor || opensResult || seedsLibrary }
    static var initialTab: String? { UserDefaults.standard.string(forKey: "tab") }
}

/// Renders drifting neon light blobs so the editor has something to show without a real video.
nonisolated enum DemoVideo {
    @concurrent
    static func make() async throws -> URL {
        let width = 720, height = 1280, fps: Int32 = 30, frameCount = 150
        let url = URL.temporaryDirectory.appending(path: "demo-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
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
        let blobs: [(r: CGFloat, g: CGFloat, b: CGFloat, phase: CGFloat)] = [
            (0, 0.94, 1, 0), (0.54, 0.17, 0.89, 2.1), (1, 0, 0.5, 4.2),
        ]
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) {
                context.setFillColor(red: 0.04, green: 0.04, blue: 0.055, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                let t = CGFloat(frame) / CGFloat(frameCount) * 2 * .pi
                for blob in blobs {
                    let center = CGPoint(
                        x: CGFloat(width) * (0.5 + 0.32 * cos(t + blob.phase)),
                        y: CGFloat(height) * (0.5 + 0.3 * sin(t * 1.3 + blob.phase))
                    )
                    let gradient = CGGradient(colorsSpace: colorSpace, colors: [
                        CGColor(srgbRed: blob.r, green: blob.g, blue: blob.b, alpha: 0.9),
                        CGColor(srgbRed: blob.r, green: blob.g, blue: blob.b, alpha: 0),
                    ] as CFArray, locations: [0, 1])!
                    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 420, options: [])
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
        return url
    }
}
#endif
