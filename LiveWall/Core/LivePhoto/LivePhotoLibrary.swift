import AVFoundation
import Photos
import PhotosUI
import SwiftUI

nonisolated enum LivePhotoSaver {
    static func save(_ result: LivePhotoResult) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw LivePhotoError.photoLibraryDenied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: result.imageURL, options: nil)
            request.addResource(with: .pairedVideo, fileURL: result.videoURL, options: nil)
        }
    }
}

nonisolated enum LivePhotoLoader {
    /// Also serves as validation: Photos only returns a Live Photo for a correctly paired still and movie.
    static func load(_ result: LivePhotoResult, targetSize: CGSize = WallpaperFormat.outputSize) async throws -> PHLivePhoto {
        let gate = ResumeGate()
        return try await withCheckedThrowingContinuation { continuation in
            // PHImageManagerMaximumSize crashes this API, so a real size is required.
            PHLivePhoto.request(
                withResourceFileURLs: [result.imageURL, result.videoURL],
                placeholderImage: nil,
                targetSize: targetSize,
                contentMode: .aspectFill
            ) { livePhoto, info in
                if let error = info[PHLivePhotoInfoErrorKey] as? Error {
                    if gate.claim() { continuation.resume(throwing: error) }
                    return
                }
                if (info[PHLivePhotoInfoIsDegradedKey] as? Bool) == true { return }
                guard gate.claim() else { return }
                if let livePhoto {
                    continuation.resume(returning: livePhoto)
                } else {
                    continuation.resume(throwing: LivePhotoError.invalidLivePhoto)
                }
            }
        }
    }
}

/// The request handler can fire several times; this makes sure the continuation resumes once.
nonisolated private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}

struct LivePhotoView: UIViewRepresentable {
    let livePhoto: PHLivePhoto?

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        guard view.livePhoto !== livePhoto else { return }
        view.livePhoto = livePhoto
        // Plays once on arrival, unless the person has turned off Auto-Play Video Previews.
        if livePhoto != nil, UIAccessibility.isVideoAutoplayEnabled { view.startPlayback(with: .full) }
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
