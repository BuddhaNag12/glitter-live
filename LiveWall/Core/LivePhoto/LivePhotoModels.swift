import CoreMedia
import Foundation

nonisolated struct LivePhotoRequest: Sendable {
    var sourceURL: URL
    var timeRange: CMTimeRange
    /// Normalized (0...1) to the upright video frame.
    var cropRect: CGRect
    /// Measured from `timeRange.start`, in source time.
    var keyFrameOffset: CMTime
    var speed: Double = 1
    /// Plays the clip forward, then in reverse.
    var bounces = false
    var outputSize: CGSize = WallpaperFormat.outputSize
}

nonisolated struct LivePhotoResult: Sendable, Hashable {
    let identifier: String
    let imageURL: URL
    let videoURL: URL
}

nonisolated enum LivePhotoError: LocalizedError {
    case noVideoTrack
    case emptyTimeRange
    case readerFailed((any Error)?)
    case writerFailed((any Error)?)
    case imageEncodingFailed
    case invalidLivePhoto
    case photoLibraryDenied

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "This file doesn't contain a video."
        case .emptyTimeRange: "The selected clip is empty."
        case .readerFailed(let error): error?.localizedDescription ?? "The video couldn't be read."
        case .writerFailed(let error): error?.localizedDescription ?? "The Live Photo video couldn't be written."
        case .imageEncodingFailed: "The cover image couldn't be created."
        case .invalidLivePhoto: "iOS didn't accept the generated Live Photo."
        case .photoLibraryDenied: "Allow Glitter Live to add photos in Settings to save wallpapers."
        }
    }
}

extension URL {
    nonisolated static var livePhotosDirectory: URL {
        URL.temporaryDirectory.appending(path: "LivePhotos", directoryHint: .isDirectory)
    }
}
