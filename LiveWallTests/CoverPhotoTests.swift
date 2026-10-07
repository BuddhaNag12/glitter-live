import AVFoundation
import ImageIO
import Testing
@testable import LiveWall

@Suite(.timeLimit(.minutes(5)))
struct CoverPhotoTests {
    @Test func stillUsesTheSourceResolutionUpToTheLargestScreen() {
        let output = WallpaperFormat.outputSize
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)

        let large = LivePhotoBuilder.stillSize(uprightSourceSize: CGSize(width: 2160, height: 3840), cropRect: full, outputSize: output)
        #expect(large.width == WallpaperFormat.maximumStillWidth)

        let medium = LivePhotoBuilder.stillSize(uprightSourceSize: CGSize(width: 1080, height: 2340), cropRect: full, outputSize: output)
        #expect(medium.width == 1080)

        let small = LivePhotoBuilder.stillSize(uprightSourceSize: CGSize(width: 1280, height: 720), cropRect: CGRect(x: 0.3, y: 0, width: 0.4, height: 1), outputSize: output)
        #expect(small.width == output.width)

        for size in [large, medium, small] {
            #expect(abs(size.width / size.height - output.width / output.height) < 0.002)
            #expect(size.width.truncatingRemainder(dividingBy: 2) == 0 && size.height.truncatingRemainder(dividingBy: 2) == 0)
        }
    }

    @Test func stillIsSharperThanTheMovieAndShowsTheSameFrame() async throws {
        // 8 gray levels per frame: a neighbouring frame would differ by about 8.
        let source = try await SyntheticVideo.make(size: CGSize(width: 1440, height: 3120), seconds: 3, step: 8)
        let request = LivePhotoRequest(
            sourceURL: source,
            timeRange: CMTimeRange(start: CMTime(seconds: 0.5, preferredTimescale: 600), duration: CMTime(seconds: 2, preferredTimescale: 600)),
            cropRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            keyFrameOffset: CMTime(seconds: 1, preferredTimescale: 600)
        )
        let result = try await LivePhotoBuilder.build(request, in: URL.temporaryDirectory.appending(path: "CoverTests-\(UUID().uuidString)", directoryHint: .isDirectory))

        let imageSource = try #require(CGImageSourceCreateWithURL(result.imageURL as CFURL, nil))
        let still = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        #expect(CGFloat(still.width) == WallpaperFormat.maximumStillWidth)
        #expect(CGFloat(still.width) > WallpaperFormat.outputSize.width)

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: result.videoURL))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let movieFrame = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        #expect(abs(meanGray(still) - meanGray(movieFrame)) < 3)
    }

    private func meanGray(_ image: CGImage) -> Double {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        let reds = stride(from: 0, to: pixels.count, by: 4).map { Double(pixels[$0]) }
        return reds.reduce(0, +) / Double(reds.count)
    }
}
