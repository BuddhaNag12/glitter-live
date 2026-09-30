import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import VideoToolbox

/// Turns a video clip into a paired still + movie that Photos recognizes as a Live Photo and the
/// Lock Screen accepts as a moving wallpaper. The pairing is a shared UUID: MakerApple key 17 in
/// the still, and the QuickTime content identifier in the movie. Wallpaper motion additionally
/// needs HEVC video and the timed metadata in `LivePhotoMetadata`.
nonisolated enum LivePhotoBuilder {
    private static let frameDuration = CMTime(value: 1, timescale: WallpaperFormat.frameRate)
    /// Reverse playback decodes the clip in short chunks so only a few frames are held in memory.
    private static let reverseChunk = CMTime(value: 1, timescale: 4)

    @concurrent
    static func build(_ request: LivePhotoRequest, in directory: URL) async throws -> LivePhotoResult {
        let identifier = UUID().uuidString
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let videoURL = directory.appending(path: "\(identifier).mov")
        let clip = try await Clip(request)
        let stillTime = try await writeVideo(clip, request, identifier: identifier, to: videoURL)
        let imageURL = try await writeStill(clip, at: stillTime, movie: videoURL, identifier: identifier, in: directory)
        return LivePhotoResult(identifier: identifier, imageURL: imageURL, videoURL: videoURL)
    }

    /// Size of the cover photo: the crop at the source's own resolution, between the movie's size and
    /// the largest iPhone screen. The Lock Screen accepts a still larger than the movie as long as it
    /// shows the same frame, and it's what people see almost all the time.
    static func stillSize(uprightSourceSize: CGSize, cropRect: CGRect, outputSize: CGSize) -> CGSize {
        let cropWidth = cropRect.width * uprightSourceSize.width
        let width = min(max(cropWidth, outputSize.width), WallpaperFormat.maximumStillWidth)
        let evenWidth = (width / 2).rounded(.down) * 2
        let evenHeight = (evenWidth * outputSize.height / outputSize.width / 2).rounded() * 2
        return CGSize(width: evenWidth, height: evenHeight)
    }

    /// Returns the cover frame's time in the written movie.
    private static func writeVideo(_ clip: Clip, _ request: LivePhotoRequest, identifier: String, to url: URL) async throws -> CMTime {
        let renderSize = request.outputSize
        let forwardDuration = clip.forwardDuration
        let composition = clip.composition
        let track = clip.track
        let videoComposition = clip.videoComposition(renderSize: renderSize)

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.metadata = [contentIdentifierItem(identifier)]
        let bt709: [String: Any] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
        // 8-bit SDR HEVC Main: the Lock Screen rejects H.264, and Photos flags 10-bit HDR output.
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoColorPropertiesKey: bt709,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String,
                AVVideoExpectedSourceFrameRateKey: WallpaperFormat.frameRate,
                AVVideoMaxKeyFrameIntervalKey: WallpaperFormat.frameRate,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ])
        let pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        let infoFormat = try LivePhotoMetadata.infoFormatDescription()
        let stillFormat = try LivePhotoMetadata.stillFormatDescription()
        let infoInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: infoFormat)
        let stillInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: stillFormat)
        for input in [videoInput, infoInput, stillInput] {
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw LivePhotoError.writerFailed(nil) }
            writer.add(input)
        }

        guard writer.startWriting() else { throw LivePhotoError.writerFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        let requestedStill = CMTimeMultiplyByFloat64(request.keyFrameOffset, multiplier: 1 / request.speed)
        let earliestStill = CMTimeMinimum(CMTime(seconds: WallpaperFormat.minimumCoverTime, preferredTimescale: 600), forwardDuration - frameDuration)
        let clampedStill = CMTimeClampToRange(requestedStill, range: CMTimeRange(start: earliestStill, end: forwardDuration - frameDuration))
        // Snap to a movie frame so the still, rendered separately from the source, is the same frame.
        let frameIndex = CMTimeValue((clampedStill.seconds * Double(WallpaperFormat.frameRate)).rounded(.down))
        // In the video's timescale AVAssetWriter drops the empty edit that delays this sample, so it
        // would land at 0 s, which the Lock Screen rejects. Apple's own files use 600.
        let stillTime = CMTimeConvertScale(CMTime(value: frameIndex, timescale: WallpaperFormat.frameRate), timescale: 600, method: .roundHalfAwayFromZero)
        guard stillInput.append(try LivePhotoMetadata.stillSample(format: stillFormat, at: stillTime)) else {
            throw LivePhotoError.writerFailed(writer.error)
        }
        stillInput.markAsFinished()

        func append(_ buffer: CVPixelBuffer, at time: CMTime) async throws {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard pixelAdaptor.append(buffer, withPresentationTime: time) else {
                throw LivePhotoError.writerFailed(writer.error)
            }
            while !infoInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let info = try LivePhotoMetadata.infoSample(format: infoFormat, at: time, duration: frameDuration)
            guard infoInput.append(info) else { throw LivePhotoError.writerFailed(writer.error) }
        }

        do {
            let forward = try FrameReader(asset: composition, track: track, videoComposition: videoComposition)
            while let frame = try forward.next() {
                try await append(frame.buffer, at: frame.time)
            }

            if request.bounces {
                // A forward frame at t plays again at 2·D − frameDuration − t, so the reversed half
                // starts right where the forward half ends.
                let mirror = forwardDuration + forwardDuration - frameDuration
                var chunkEnd = forwardDuration
                while chunkEnd > .zero {
                    let chunkStart = CMTimeMaximum(.zero, chunkEnd - reverseChunk)
                    let chunk = CMTimeRange(start: chunkStart, end: chunkEnd)
                    let reader = try FrameReader(asset: composition, track: track, videoComposition: videoComposition, timeRange: chunk)
                    var frames: [(buffer: CVPixelBuffer, time: CMTime)] = []
                    while let frame = try reader.next() {
                        if frame.time >= chunkStart, frame.time < chunkEnd { frames.append(frame) }
                    }
                    for frame in frames.reversed() {
                        try await append(frame.buffer, at: mirror - frame.time)
                    }
                    chunkEnd = chunkStart
                }
            }
        } catch {
            writer.cancelWriting()
            throw error
        }

        videoInput.markAsFinished()
        infoInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw LivePhotoError.writerFailed(writer.error) }
        return stillTime
    }

    private static func writeStill(_ clip: sending Clip, at time: CMTime, movie: URL, identifier: String, in directory: URL) async throws -> URL {
        let image: CGImage
        do {
            // Rendered from the source rather than the encoded movie, so it's sharper and has no compression artifacts.
            let generator = AVAssetImageGenerator(asset: clip.composition)
            generator.videoComposition = clip.videoComposition(renderSize: clip.stillSize)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            image = try await generator.image(at: time).image
        } catch {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            image = try await generator.image(at: time).image
        }

        // Some simulators can't encode HEIC, so fall back to JPEG.
        for (type, fileExtension) in [(UTType.heic, "heic"), (UTType.jpeg, "jpg")] {
            let url = directory.appending(path: "\(identifier).\(fileExtension)")
            if writeImage(image, as: type, identifier: identifier, to: url) { return url }
        }
        throw LivePhotoError.imageEncodingFailed
    }

    private static func writeImage(_ image: CGImage, as type: UTType, identifier: String, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            return false
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": identifier],
            kCGImageDestinationLossyCompressionQuality: 0.92,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// Maps the source track into the render frame so that `cropRect` fills it exactly.
    static func cropTransform(naturalSize: CGSize, preferredTransform: CGAffineTransform, cropRect: CGRect, renderSize: CGSize) -> CGAffineTransform {
        let upright = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let crop = CGRect(
            x: cropRect.minX * upright.width,
            y: cropRect.minY * upright.height,
            width: cropRect.width * upright.width,
            height: cropRect.height * upright.height
        )
        return preferredTransform
            .concatenating(CGAffineTransform(translationX: -upright.minX - crop.minX, y: -upright.minY - crop.minY))
            .concatenating(CGAffineTransform(scaleX: renderSize.width / crop.width, y: renderSize.height / crop.height))
    }

    private static func contentIdentifierItem(_ identifier: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeMetadataContentIdentifier
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        item.value = identifier as NSString
        return item
    }
}

/// A request's trimmed and retimed clip, shared by the movie and the cover photo.
nonisolated private struct Clip {
    let composition: AVMutableComposition
    let track: AVMutableCompositionTrack
    let forwardDuration: CMTime
    let stillSize: CGSize
    private let naturalSize: CGSize
    private let preferredTransform: CGAffineTransform
    private let cropRect: CGRect

    init(_ request: LivePhotoRequest) async throws {
        let source = AVURLAsset(url: request.sourceURL)
        guard let sourceTrack = try await source.loadTracks(withMediaType: .video).first else {
            throw LivePhotoError.noVideoTrack
        }
        let (naturalSize, preferredTransform, sourceRange) = try await sourceTrack.load(.naturalSize, .preferredTransform, .timeRange)
        let range = request.timeRange.intersection(sourceRange)
        guard range.duration > .zero, request.speed > 0 else { throw LivePhotoError.emptyTimeRange }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw LivePhotoError.noVideoTrack
        }
        try track.insertTimeRange(range, of: sourceTrack, at: .zero)
        let forwardDuration = CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / request.speed)
        if request.speed != 1 {
            composition.scaleTimeRange(CMTimeRange(start: .zero, duration: range.duration), toDuration: forwardDuration)
        }

        let upright = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        self.composition = composition
        self.track = track
        self.forwardDuration = forwardDuration
        self.naturalSize = naturalSize
        self.preferredTransform = preferredTransform
        self.cropRect = request.cropRect
        self.stillSize = LivePhotoBuilder.stillSize(
            uprightSourceSize: CGSize(width: abs(upright.width), height: abs(upright.height)),
            cropRect: request.cropRect,
            outputSize: request.outputSize
        )
    }

    func videoComposition(renderSize: CGSize) -> AVMutableVideoComposition {
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(
            LivePhotoBuilder.cropTransform(naturalSize: naturalSize, preferredTransform: preferredTransform, cropRect: cropRect, renderSize: renderSize),
            at: .zero
        )
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: forwardDuration)
        instruction.layerInstructions = [layerInstruction]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: WallpaperFormat.frameRate)
        videoComposition.instructions = [instruction]
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        return videoComposition
    }
}

/// Decodes composited frames of a clip, optionally limited to a time range.
nonisolated private final class FrameReader {
    private let reader: AVAssetReader
    private let output: AVAssetReaderVideoCompositionOutput

    init(asset: AVAsset, track: AVAssetTrack, videoComposition: AVVideoComposition, timeRange: CMTimeRange? = nil) throws {
        reader = try AVAssetReader(asset: asset)
        if let timeRange { reader.timeRange = timeRange }
        output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        output.videoComposition = videoComposition
        // Reversed frames are held after the reader moves on, so they must not alias its buffer pool.
        output.alwaysCopiesSampleData = timeRange != nil
        guard reader.canAdd(output) else { throw LivePhotoError.readerFailed(nil) }
        reader.add(output)
        guard reader.startReading() else { throw LivePhotoError.readerFailed(reader.error) }
    }

    func next() throws -> (buffer: CVPixelBuffer, time: CMTime)? {
        try Task.checkCancellation()
        while let sample = output.copyNextSampleBuffer() {
            if let buffer = CMSampleBufferGetImageBuffer(sample) {
                return (buffer, CMSampleBufferGetPresentationTimeStamp(sample))
            }
        }
        if reader.status == .failed { throw LivePhotoError.readerFailed(reader.error) }
        return nil
    }

    deinit {
        if reader.status == .reading { reader.cancelReading() }
    }
}
