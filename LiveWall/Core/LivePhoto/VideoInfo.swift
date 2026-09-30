import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

nonisolated struct VideoInfo: Sendable {
    let duration: Double
    /// Size after applying the track's rotation.
    let uprightSize: CGSize

    static func load(_ url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw LivePhotoError.noVideoTrack }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let duration = try await asset.load(.duration)
        let upright = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return VideoInfo(duration: duration.seconds, uprightSize: CGSize(width: abs(upright.width), height: abs(upright.height)))
    }
}

/// A video picked from Photos, copied somewhere the app controls.
nonisolated struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let directory = URL.temporaryDirectory.appending(path: "Imports", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appending(path: "\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedVideo(url: destination)
        }
    }
}
