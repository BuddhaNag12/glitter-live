import CoreGraphics
import CoreMedia
import Foundation

/// The Supabase project behind Explore. The publishable key is meant to ship in apps; the
/// `wallpapers` table only allows reading published rows with it.
nonisolated enum CatalogConfig {
    static let projectURL = URL(string: "https://jusrioirjfpaocgmsbbv.supabase.co")!
    static let publishableKey = "sb_publishable_H8JSLO_Abl7S2ocPsk1LSQ_OT3w-Xny"
    static let bucket = "wallpapers"

    static func publicFileURL(_ path: String) -> URL {
        projectURL.appending(path: "storage/v1/object/public/\(bucket)/\(path)")
    }
}

nonisolated struct Wallpaper: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let category: String
    let videoPath: String
    let thumbnailPath: String
    let durationSeconds: Double
    let width: Int
    let height: Int
    let creatorName: String?
    let creatorURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, title, category, width, height
        case videoPath = "video_path"
        case thumbnailPath = "thumbnail_path"
        case durationSeconds = "duration_seconds"
        case creatorName = "creator_name"
        case creatorURL = "creator_url"
    }

    var videoURL: URL { CatalogConfig.publicFileURL(videoPath) }
    var thumbnailURL: URL { CatalogConfig.publicFileURL(thumbnailPath) }
}

nonisolated enum CatalogError: LocalizedError {
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse(let status): "The wallpaper catalog isn't available right now (error \(status)). Try again in a moment."
        }
    }
}

nonisolated enum CatalogService {
    static func fetchWallpapers() async throws -> [Wallpaper] {
        var components = URLComponents(url: CatalogConfig.projectURL.appending(path: "rest/v1/wallpapers"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,title,category,video_path,thumbnail_path,duration_seconds,width,height,creator_name,creator_url"),
            URLQueryItem(name: "order", value: "sort_order.asc,created_at.desc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(CatalogConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.cachePolicy = .reloadRevalidatingCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw CatalogError.badResponse(status) }
        return try JSONDecoder().decode([Wallpaper].self, from: data)
    }

    /// Downloads the video once; later saves of the same wallpaper reuse the cached file.
    static func downloadVideo(_ wallpaper: Wallpaper) async throws -> URL {
        let directory = URL.cachesDirectory.appending(path: "Wallpapers", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "\(wallpaper.id.uuidString).\(wallpaper.videoURL.pathExtension)")
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) { return destination }

        let (temporary, response) = try await URLSession.shared.download(from: wallpaper.videoURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw CatalogError.badResponse(status) }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}

extension LivePhotoRequest {
    /// The whole clip (up to the Lock Screen's 5 s limit), center-cropped to fill the screen,
    /// with the cover photo at the midpoint.
    nonisolated static func filling(source: URL, uprightSize: CGSize, duration: Double) -> LivePhotoRequest {
        let length = min(duration, 5)
        return LivePhotoRequest(
            sourceURL: source,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: length, preferredTimescale: 600)),
            cropRect: centerCrop(for: uprightSize),
            keyFrameOffset: CMTime(seconds: length / 2, preferredTimescale: 600)
        )
    }

    nonisolated static func centerCrop(for size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let target = WallpaperFormat.aspectRatio
        let aspect = size.width / size.height
        if aspect > target {
            let width = target / aspect
            return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        } else {
            let height = aspect / target
            return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        }
    }
}
