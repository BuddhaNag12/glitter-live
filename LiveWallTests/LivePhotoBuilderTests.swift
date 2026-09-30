import AVFoundation
import ImageIO
import Photos
import Testing
@testable import LiveWall

struct LivePhotoBuilderTests {

    @Test func pairsStillAndMovieWithSharedIdentifier() async throws {
        let source = try await SyntheticVideo.make(size: CGSize(width: 1280, height: 720), seconds: 4)
        let result = try await LivePhotoBuilder.build(request(source: source), in: outputDirectory())

        let metadata = try await AVURLAsset(url: result.videoURL).load(.metadata)
        let identifierItem = try #require(AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeMetadataContentIdentifier).first)
        #expect(try await identifierItem.load(.stringValue) == result.identifier)

        let imageSource = try #require(CGImageSourceCreateWithURL(result.imageURL as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        let makerApple = try #require(properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any])
        #expect(makerApple["17"] as? String == result.identifier)
    }

    @Test func writesTheMetadataTracksTheLockScreenRequires() async throws {
        let source = try await SyntheticVideo.make(size: CGSize(width: 1280, height: 720), seconds: 4)
        let result = try await LivePhotoBuilder.build(request(source: source), in: outputDirectory())

        let asset = AVURLAsset(url: result.videoURL)
        var identifiers: [String] = []
        for track in try await asset.loadTracks(withMediaType: .metadata) {
            for format in try await track.load(.formatDescriptions) {
                identifiers += (CMMetadataFormatDescriptionGetIdentifiers(format) as? [String]) ?? []
            }
        }
        #expect(identifiers.contains("mdta/com.apple.quicktime.live-photo-info"))
        #expect(identifiers.contains("mdta/com.apple.quicktime.still-image-time"))
        #expect(identifiers.contains("mdta/com.apple.quicktime.live-photo-still-image-transform"))

        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let codec = try await video.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
        #expect(codec == kCMVideoCodecType_HEVC)
    }

    @Test func rendersAtWallpaperSizeAndClipLength() async throws {
        let source = try await SyntheticVideo.make(size: CGSize(width: 1280, height: 720), seconds: 4)
        let result = try await LivePhotoBuilder.build(request(source: source), in: outputDirectory())

        let asset = AVURLAsset(url: result.videoURL)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size == WallpaperFormat.outputSize)
        #expect(max(size.width, size.height) <= 1920)
        #expect(abs(try await asset.load(.duration).seconds - 2) < 0.1)
    }

    @Test func speedAndBounceChangeOutputLength() async throws {
        let source = try await SyntheticVideo.make(size: CGSize(width: 720, height: 1280), seconds: 4)
        var request = request(source: source)
        request.speed = 2
        request.bounces = true
        let result = try await LivePhotoBuilder.build(request, in: outputDirectory())

        // 2 s of source at 2x is 1 s forward, doubled by the reverse half.
        let duration = try await AVURLAsset(url: result.videoURL).load(.duration).seconds
        #expect(abs(duration - 2) < 0.1)
    }

    @Test func photosAcceptsThePair() async throws {
        let source = try await SyntheticVideo.make(size: CGSize(width: 1280, height: 720), seconds: 4)
        let result = try await LivePhotoBuilder.build(request(source: source), in: outputDirectory())
        _ = try await LivePhotoLoader.load(result)
    }

    @Test func cropTransformMapsCropRectOntoRenderFrame() {
        let rotated = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 720, ty: 0)
        let crop = CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8)
        let render = CGSize(width: 1080, height: 2340)
        let transform = LivePhotoBuilder.cropTransform(
            naturalSize: CGSize(width: 1280, height: 720),
            preferredTransform: rotated,
            cropRect: crop,
            renderSize: render
        )
        // In upright space the video is 720×1280; the crop's corners must land on the render corners.
        let uprightToNatural = rotated.inverted()
        let topLeft = CGPoint(x: 0.25 * 720, y: 0.1 * 1280).applying(uprightToNatural).applying(transform)
        let bottomRight = CGPoint(x: 0.75 * 720, y: 0.9 * 1280).applying(uprightToNatural).applying(transform)
        #expect(abs(topLeft.x) < 0.001 && abs(topLeft.y) < 0.001)
        #expect(abs(bottomRight.x - render.width) < 0.001 && abs(bottomRight.y - render.height) < 0.001)
    }

    private func request(source: URL) -> LivePhotoRequest {
        LivePhotoRequest(
            sourceURL: source,
            timeRange: CMTimeRange(start: CMTime(seconds: 0.5, preferredTimescale: 600), duration: CMTime(seconds: 2, preferredTimescale: 600)),
            cropRect: CGRect(x: 0.3, y: 0, width: 0.4, height: 1),
            keyFrameOffset: CMTime(seconds: 1, preferredTimescale: 600)
        )
    }

    private func outputDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "LivePhotoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

/// Writes a short gray-ramp movie so tests don't need fixture files.
enum SyntheticVideo {
    /// Each frame is a flat gray `step` levels brighter than the last, so frames are easy to tell apart.
    static func make(size: CGSize, seconds: Int, fps: Int32 = 30, step: Int = 3) async throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "synthetic-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<(seconds * Int(fps)) {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            let pool = try #require(adaptor.pixelBufferPool)
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixelBuffer = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            memset(CVPixelBufferGetBaseAddress(pixelBuffer), Int32(frame * step % 255), CVPixelBufferGetDataSize(pixelBuffer))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }
}
