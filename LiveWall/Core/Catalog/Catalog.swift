import CoreGraphics
import CoreMedia
import Foundation

/// The Supabase project behind Explore. The publishable key is meant to ship in apps; with it,
/// the `catalog` view and `wallpapers` table only allow reading published rows.
nonisolated enum CatalogConfig {
    static let projectURL = URL(string: "https://jusrioirjfpaocgmsbbv.supabase.co")!
    static let publishableKey = "sb_publishable_H8JSLO_Abl7S2ocPsk1LSQ_OT3w-Xny"
    static let bucket = "wallpapers"

    static func publicFileURL(_ path: String) -> URL {
        projectURL.appending(path: "storage/v1/object/public/\(bucket)/\(path)")
    }
}

nonisolated struct Wallpaper: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case live, still }

    let id: UUID
    let kind: Kind
    let title: String
    let category: String
    /// Set for live wallpapers.
    let videoPath: String?
    /// Set for stills.
    let imagePath: String?
    let thumbnailPath: String
    /// Set for live wallpapers.
    let durationSeconds: Double?
    let width: Int
    let height: Int
    let creatorName: String?
    let creatorURL: URL?
    let isFeatured: Bool
    /// Picked in the admin site as its category's cover. Optional so a catalog without the column still decodes.
    var isCategoryCover: Bool? = nil
    /// Kept as text, so a timestamp format change can't fail the whole catalog's decoding.
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, category, width, height
        case videoPath = "video_path"
        case imagePath = "image_path"
        case thumbnailPath = "thumbnail_path"
        case durationSeconds = "duration_seconds"
        case creatorName = "creator_name"
        case creatorURL = "creator_url"
        case isFeatured = "is_featured"
        case isCategoryCover = "is_category_cover"
        case createdAt = "created_at"
    }

    var isLive: Bool { kind == .live }
    var videoURL: URL? { videoPath.map(CatalogConfig.publicFileURL) }
    /// The video for a live wallpaper, the full-size image for a still.
    var mediaURL: URL { CatalogConfig.publicFileURL(videoPath ?? imagePath ?? thumbnailPath) }
    var thumbnailURL: URL { CatalogConfig.publicFileURL(thumbnailPath) }

    /// Postgres leaves out the fraction when it's zero, so both forms are read.
    var createdDate: Date? {
        guard let createdAt else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(createdAt))
            ?? (try? Date.ISO8601FormatStyle().parse(createdAt))
    }
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
        // 1.0 reads `wallpapers`, which only returns live rows; `catalog` has stills too.
        // A change that would break this decoder needs a new view (`catalog_v2`), not an edit to this one.
        var components = URLComponents(url: CatalogConfig.projectURL.appending(path: "rest/v1/catalog"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,kind,title,category,video_path,image_path,thumbnail_path,duration_seconds,width,height,creator_name,creator_url,is_featured,is_category_cover,created_at"),
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

    /// Downloads the video (or a still's image) once; later saves of the same wallpaper reuse the cached file.
    static func downloadMedia(_ wallpaper: Wallpaper) async throws -> URL {
        let directory = URL.cachesDirectory.appending(path: "Wallpapers", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "\(wallpaper.id.uuidString).\(wallpaper.mediaURL.pathExtension)")
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) { return destination }

        let (temporary, response) = try await URLSession.shared.download(from: wallpaper.mediaURL)
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
