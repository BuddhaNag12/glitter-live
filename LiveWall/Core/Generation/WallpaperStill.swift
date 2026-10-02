import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// The generated image framed as a Lock Screen still: cropped to the screen's shape and scaled up to the
/// same size as the live wallpapers, so a saved still and its live version match.
nonisolated enum WallpaperStill {
    static func make(from url: URL) throws -> URL {
        guard let image = CIImage(contentsOf: url) else { throw LivePhotoError.imageEncodingFailed }
        let size = WallpaperFormat.outputSize
        let scale = max(size.width / image.extent.width, size.height / image.extent.height)
        let scaled = image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        let crop = CGRect(
            x: scaled.extent.midX - size.width / 2, y: scaled.extent.midY - size.height / 2,
            width: size.width, height: size.height
        ).integral
        let output = URL.temporaryDirectory.appending(path: "wallpaper-\(UUID().uuidString).jpg")
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        try CIContext().writeJPEGRepresentation(of: scaled.cropped(to: crop), to: output, colorSpace: colorSpace, options: [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.92,
        ])
        return output
    }
}
