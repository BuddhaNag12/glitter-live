import AVFoundation
import CoreImage
import ImageIO
import Vision

/// Free, on-device motion: Apple's Depth Anything V2 estimates how far away each part of the image is, then a
/// slow camera move shifts near things more than far ones, so the still gains real depth. Falls back to a plain
/// push-in if the model isn't in the build (`scripts/fetch-depth-model.sh`).
nonisolated struct DepthMotionService: WallpaperAnimator {
    private static let modelName = "DepthAnythingV2SmallF16P6"

    @concurrent
    func animate(imageAt imageURL: URL, for request: GenerationRequest) async throws -> URL {
        guard let modelURL = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc"),
              let libraryURL = Bundle.main.url(forResource: "default", withExtension: "metallib") else {
            return try await PreviewGenerationService().animate(imageAt: imageURL, for: request)
        }
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw GenerationError.videoFailed }

        let kernel = try CIKernel(functionName: "depthParallax", fromMetalLibraryData: Data(contentsOf: libraryURL))
        let depth = try Self.depth(of: image, modelURL: modelURL)
        return try await Self.render(image: CIImage(cgImage: image), depth: depth, kernel: kernel)
    }

    /// Relative depth from 0 (farthest) to 1 (nearest), at the image's own size.
    private static func depth(of image: CGImage, modelURL: URL) throws -> CIImage {
        let model = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
        let request = VNCoreMLRequest(model: model)
        // The model was trained on stretched images, so stretch rather than crop.
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let buffer = (request.results?.first as? VNPixelBufferObservation)?.pixelBuffer else { throw GenerationError.videoFailed }

        let (low, high) = range(of: buffer)
        let scale = 1 / max(high - low, 0.0001)
        let raw = CIImage(cvPixelBuffer: buffer)
        let normalized = raw.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: -low * scale, y: 0, z: 0, w: 0),
        ])
        .clampedToExtent()
        // Widening near objects keeps their outline intact: the background slides past them instead of
        // eating into their edges, and the soft blur then hides the seam.
        .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 5])
        .applyingGaussianBlur(sigma: 2)
        .cropped(to: raw.extent)
        return normalized.transformed(by: CGAffineTransform(
            scaleX: CGFloat(image.width) / raw.extent.width,
            y: CGFloat(image.height) / raw.extent.height
        ))
    }

    /// The 2nd and 98th percentiles, so a few stray values don't flatten the rest of the map.
    private static func range(of buffer: CVPixelBuffer) -> (CGFloat, CGFloat) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return (0, 1) }
        var values: [Float] = []
        values.reserveCapacity(width * height / 4)
        // Every other pixel in each direction is plenty for a range.
        for y in stride(from: 0, to: height, by: 2) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float16.self)
            for x in stride(from: 0, to: width, by: 2) { values.append(Float(row[x])) }
        }
        values.sort()
        guard !values.isEmpty else { return (0, 1) }
        return (CGFloat(values[values.count * 2 / 100]), CGFloat(values[values.count * 98 / 100]))
    }

    private static func render(image: CIImage, depth: CIImage, kernel: CIKernel) async throws -> URL {
        let size = WallpaperFormat.outputSize
        let width = Int(size.width), height = Int(size.height)
        let fps: Int32 = 30, frameCount = 90
        // Slightly larger than the frame, so the moving edges never show.
        let fill = max(size.width / image.extent.width, size.height / image.extent.height) * 1.06
        let placement = CGAffineTransform(translationX: (size.width - image.extent.width * fill) / 2, y: (size.height - image.extent.height * fill) / 2)
            .scaledBy(x: fill, y: fill)
        let placedImage = image.transformed(by: placement).clampedToExtent()
        let placedDepth = depth.transformed(by: placement).clampedToExtent()
        let frame = CGRect(origin: .zero, size: size)
        let center = CIVector(x: size.width / 2, y: size.height / 2)

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

        let context = CIContext()
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let pool = adaptor.pixelBufferPool else { throw GenerationError.videoFailed }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw GenerationError.videoFailed }

            // A gentle push in with the background drifting behind the subject, eased so it starts and settles
            // softly. The nearest things sit at the focus depth, so the subject itself never warps.
            let eased = CGFloat(0.5 - cos(Double(index) / Double(frameCount - 1) * .pi) / 2)
            let output = kernel.apply(
                extent: frame,
                roiCallback: { _, rect in rect.insetBy(dx: -120, dy: -120) },
                arguments: [
                    placedImage, placedDepth,
                    CIVector(x: 44 * eased, y: 20 * eased),
                    0.05 * eased,
                    1 + 0.06 * eased,
                    center,
                    0.85,
                ]
            )
            guard let output else { throw GenerationError.videoFailed }
            context.render(output, to: buffer, bounds: frame, colorSpace: colorSpace)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
        return url
    }
}
