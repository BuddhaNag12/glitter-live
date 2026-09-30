import AVFoundation
import Observation

@Observable
final class ConvertEditor {
    enum Phase: Equatable {
        case loading
        case editing
        case exporting
        case finished(LivePhotoResult, saved: Bool)
        case unavailable(String)
    }

    static let speeds: [Double] = [0.5, 1, 1.5, 2]
    static let zoomRange: ClosedRange<CGFloat> = 1...4
    private static let outputDurationRange = 1.0...3.0

    let sourceURL: URL
    private(set) var phase: Phase = .loading
    private(set) var duration: Double = 0
    private(set) var uprightSize: CGSize = .zero
    private(set) var thumbnails: [CGImage] = []

    /// Clip window and cover frame, in source seconds. The cover offset is relative to `clipStart`.
    private(set) var clipStart: Double = 0
    private(set) var clipLength: Double = 0
    var coverOffset: Double = 0

    var speed: Double = 1 {
        didSet { clampClip(); restartLoop() }
    }
    var bounces = false {
        didSet { clampClip(); restartLoop() }
    }
    var showsLockScreen = true

    /// Framing inside the preview canvas: zoom ≥ 1 relative to aspect-fill, pan in canvas points.
    var zoom: CGFloat = 1
    var panOffset: CGSize = .zero
    var canvasSize: CGSize = .zero

    var errorMessage: String?

    let player = AVQueuePlayer()
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private let library: CreationLibrary?
    @ObservationIgnored private var creation: Creation?
    @ObservationIgnored private var initialEdits: Edits?
    @ObservationIgnored private var scrubTarget: CMTime?
    @ObservationIgnored private var isSeeking = false

    init(sourceURL: URL, library: CreationLibrary? = nil) {
        self.sourceURL = sourceURL
        self.library = library
        player.isMuted = true
    }

    var outputDuration: Double { clipLength / speed * (bounces ? 2 : 1) }

    var coverRange: ClosedRange<Double> {
        min(WallpaperFormat.minimumCoverTime * speed, clipLength)...max(clipLength, 0.01)
    }

    private var outputToSource: Double { speed / (bounces ? 2 : 1) }
    var maxClipLength: Double { min(duration, Self.outputDurationRange.upperBound * outputToSource) }
    var minClipLength: Double { min(maxClipLength, Self.outputDurationRange.lowerBound * outputToSource) }

    private var clipRange: CMTimeRange {
        CMTimeRange(start: CMTime(seconds: clipStart, preferredTimescale: 600), duration: CMTime(seconds: clipLength, preferredTimescale: 600))
    }

    func load() async {
        // Trim Studio reappears after "Edit Again", which must keep the edits rather than start over.
        guard phase == .loading else { return }
        do {
            let info = try await VideoInfo.load(sourceURL)
            duration = info.duration
            uprightSize = info.uprightSize
            clipLength = maxClipLength
            coverOffset = clipLength / 2
            initialEdits = edits
            phase = .editing
            restartLoop()
            thumbnails = await makeThumbnails()
        } catch {
            phase = .unavailable(error.localizedDescription)
        }
    }

    private struct Edits: Equatable {
        var clipStart: Double, clipLength: Double, coverOffset: Double, speed: Double, bounces: Bool
        var zoom: CGFloat, panOffset: CGSize
    }

    private var edits: Edits {
        Edits(clipStart: clipStart, clipLength: clipLength, coverOffset: coverOffset, speed: speed, bounces: bounces, zoom: zoom, panOffset: panOffset)
    }

    /// Whether closing would throw away anything the person chose.
    var hasChanges: Bool { initialEdits.map { $0 != edits } ?? false }

    // MARK: Trimming

    func moveClip(to start: Double) {
        clipStart = min(max(start, 0), max(0, duration - clipLength))
    }

    /// Drags the left handle, keeping the clip's end fixed.
    func setClipStart(_ start: Double) {
        let end = clipStart + clipLength
        let newStart = min(max(start, max(0, end - maxClipLength)), end - minClipLength)
        clipStart = newStart
        clipLength = end - newStart
        coverOffset = min(coverOffset, clipLength)
    }

    /// Drags the right handle, keeping the clip's start fixed.
    func setClipEnd(_ end: Double) {
        let newEnd = min(max(end, clipStart + minClipLength), min(duration, clipStart + maxClipLength))
        clipLength = newEnd - clipStart
        coverOffset = min(coverOffset, clipLength)
    }

    private func clampClip() {
        clipLength = min(max(clipLength, minClipLength), maxClipLength)
        moveClip(to: clipStart)
        coverOffset = min(max(coverOffset, coverRange.lowerBound), coverRange.upperBound)
    }

    // MARK: Framing

    func displayedVideoSize(zoom: CGFloat) -> CGSize {
        let canvas = effectiveCanvas
        guard uprightSize.width > 0, uprightSize.height > 0 else { return canvas }
        let scale = max(canvas.width / uprightSize.width, canvas.height / uprightSize.height) * zoom
        return CGSize(width: uprightSize.width * scale, height: uprightSize.height * scale)
    }

    /// Keeps the video covering the whole canvas.
    func clampedPan(_ pan: CGSize, zoom: CGFloat) -> CGSize {
        let limit = panLimit(zoom: zoom)
        return CGSize(width: min(max(pan.width, -limit.width), limit.width), height: min(max(pan.height, -limit.height), limit.height))
    }

    /// Mid-gesture pan: resists past the video's edges instead of stopping there.
    func rubberBandedPan(_ pan: CGSize, zoom: CGFloat) -> CGSize {
        let limit = panLimit(zoom: zoom)
        let canvas = effectiveCanvas
        return CGSize(
            width: Motion.rubberBand(pan.width, in: -limit.width...limit.width, dimension: canvas.width),
            height: Motion.rubberBand(pan.height, in: -limit.height...limit.height, dimension: canvas.height)
        )
    }

    /// Mid-gesture zoom: resists past 1× and 4× instead of stopping there.
    static func rubberBandedZoom(_ zoom: CGFloat) -> CGFloat {
        Motion.rubberBand(zoom, in: zoomRange, dimension: zoom < zoomRange.lowerBound ? 0.5 : 2)
    }

    static func unrubberBandedZoom(_ shown: CGFloat) -> CGFloat {
        Motion.unrubberBand(shown, in: zoomRange, dimension: shown < zoomRange.lowerBound ? 0.5 : 2)
    }

    func unrubberBandedPan(_ shown: CGSize, zoom: CGFloat) -> CGSize {
        let limit = panLimit(zoom: zoom)
        let canvas = effectiveCanvas
        return CGSize(
            width: Motion.unrubberBand(shown.width, in: -limit.width...limit.width, dimension: canvas.width),
            height: Motion.unrubberBand(shown.height, in: -limit.height...limit.height, dimension: canvas.height)
        )
    }

    private func panLimit(zoom: CGFloat) -> CGSize {
        let canvas = effectiveCanvas
        let displayed = displayedVideoSize(zoom: zoom)
        return CGSize(width: max(0, (displayed.width - canvas.width) / 2), height: max(0, (displayed.height - canvas.height) / 2))
    }

    /// The visible part of the video, normalized to its upright frame.
    var cropRect: CGRect {
        let canvas = effectiveCanvas
        let displayed = displayedVideoSize(zoom: zoom)
        let originX = (canvas.width - displayed.width) / 2 + panOffset.width
        let originY = (canvas.height - displayed.height) / 2 + panOffset.height
        return CGRect(
            x: -originX / displayed.width,
            y: -originY / displayed.height,
            width: canvas.width / displayed.width,
            height: canvas.height / displayed.height
        )
    }

    private var effectiveCanvas: CGSize {
        canvasSize.width > 0 && canvasSize.height > 0 ? canvasSize : WallpaperFormat.outputSize
    }

    // MARK: Preview playback

    func restartLoop() {
        guard duration > 0, clipLength > 0 else { return }
        scrubTarget = nil
        looper?.disableLooping()
        player.removeAllItems()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: sourceURL), timeRange: clipRange)
        resumePreview()
    }

    func showCoverFrame() {
        scrub(to: clipStart + coverOffset)
    }

    /// Pauses on an exact frame. Seeks wait for the previous one, so a fast drag doesn't queue up stale frames.
    func scrub(to seconds: Double) {
        player.pause()
        scrubTarget = CMTime(seconds: seconds, preferredTimescale: 600)
        seekToScrubTarget()
    }

    private func seekToScrubTarget() {
        guard !isSeeking, let target = scrubTarget else { return }
        scrubTarget = nil
        isSeeking = true
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                self.isSeeking = false
                self.seekToScrubTarget()
            }
        }
    }

    func resumePreview() {
        scrubTarget = nil
        player.defaultRate = Float(speed)
        player.play()
    }

    // MARK: Export

    func export() async {
        guard phase == .editing else { return }
        phase = .exporting
        player.pause()
        let request = LivePhotoRequest(
            sourceURL: sourceURL,
            timeRange: clipRange,
            cropRect: cropRect,
            keyFrameOffset: CMTime(seconds: coverOffset, preferredTimescale: 600),
            speed: speed,
            bounces: bounces
        )
        do {
            var result = try await LivePhotoBuilder.build(request, in: .livePhotosDirectory)
            // A library failure shouldn't block saving to Photos, so fall back to the temporary files.
            if let library, let creation = try? library.add(result, duration: outputDuration) {
                self.creation = creation
                result = creation.livePhoto
            }
            await save(result)
        } catch {
            errorMessage = error.localizedDescription
            phase = .editing
            resumePreview()
        }
    }

    func save(_ result: LivePhotoResult) async {
        do {
            try await LivePhotoSaver.save(result)
            if let creation, creation.livePhoto == result {
                creation.savedToPhotos = true
                try? library?.context.save()
            }
            phase = .finished(result, saved: true)
        } catch {
            errorMessage = error.localizedDescription
            phase = .finished(result, saved: false)
        }
    }

    #if DEBUG
    /// Builds without saving to Photos, so screenshot tests don't hit the permission prompt.
    func showDemoResult() async {
        let request = LivePhotoRequest(
            sourceURL: sourceURL, timeRange: clipRange, cropRect: cropRect,
            keyFrameOffset: CMTime(seconds: coverOffset, preferredTimescale: 600)
        )
        guard let result = try? await LivePhotoBuilder.build(request, in: .livePhotosDirectory) else { return }
        phase = .finished(result, saved: true)
    }
    #endif

    func returnToEditing() {
        phase = .editing
        resumePreview()
    }

    func stop() {
        looper?.disableLooping()
        player.removeAllItems()
    }

    private func makeThumbnails() async -> [CGImage] {
        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        let count = min(60, max(8, Int((duration * 1.2).rounded(.up))))
        let times = (0..<count).map {
            CMTime(seconds: duration * (Double($0) + 0.5) / Double(count), preferredTimescale: 600)
        }
        var images: [CGImage] = []
        for await result in generator.images(for: times) {
            if let image = try? result.image { images.append(image) }
        }
        return images
    }
}
