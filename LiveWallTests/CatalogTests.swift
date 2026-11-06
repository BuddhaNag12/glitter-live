import CoreGraphics
import Foundation
import Testing
@testable import LiveWall

struct CatalogTests {
    @Test func decodesCatalogRowsAndBuildsPublicURLs() throws {
        let json = """
        [{"id":"09829bfe-fe0e-4167-939e-fcccbeb19b41","kind":"live","title":"Silver Shimmer","category":"Glitter Originals",
          "video_path":"videos/09829bfe.mp4","image_path":null,"thumbnail_path":"thumbnails/09829bfe.jpg","duration_seconds":4,
          "width":1080,"height":1920,"creator_name":"Glitter Live","creator_url":null,"is_featured":false,
          "created_at":"2026-09-30T11:00:39.530395+00:00"}]
        """
        let wallpapers = try JSONDecoder().decode([Wallpaper].self, from: Data(json.utf8))
        let wallpaper = try #require(wallpapers.first)
        #expect(wallpaper.title == "Silver Shimmer")
        #expect(wallpaper.creatorURL == nil)
        #expect(wallpaper.isLive)
        #expect(wallpaper.videoURL?.absoluteString == "https://jusrioirjfpaocgmsbbv.supabase.co/storage/v1/object/public/wallpapers/videos/09829bfe.mp4")
        #expect(wallpaper.mediaURL == wallpaper.videoURL)
        let created = try #require(wallpaper.createdDate)
        #expect(abs(created.timeIntervalSince(try Date.ISO8601FormatStyle().parse("2026-09-30T11:00:39Z")) - 0.53) < 0.01)
    }

    @Test func decodesAStillRow() throws {
        let json = """
        [{"id":"5a1d2c3e-0000-4000-8000-000000000001","kind":"still","title":"Moonlit Bay","category":"Stills",
          "video_path":null,"image_path":"images/5a1d2c3e.png","thumbnail_path":"thumbnails/5a1d2c3e.jpg","duration_seconds":null,
          "width":1179,"height":2556,"creator_name":null,"creator_url":null,"is_featured":true}]
        """
        let wallpaper = try #require(try JSONDecoder().decode([Wallpaper].self, from: Data(json.utf8)).first)
        #expect(!wallpaper.isLive)
        #expect(wallpaper.isFeatured)
        #expect(wallpaper.videoURL == nil)
        #expect(wallpaper.durationSeconds == nil)
        #expect(wallpaper.mediaURL.absoluteString == "https://jusrioirjfpaocgmsbbv.supabase.co/storage/v1/object/public/wallpapers/images/5a1d2c3e.png")
    }

    /// Hits the live catalog: downloads the first wallpaper and builds a Live Photo from it, without saving.
    @Test(.timeLimit(.minutes(1))) func buildsALivePhotoFromTheLiveCatalog() async throws {
        let wallpaper = try #require(try await CatalogService.fetchWallpapers().first(where: \.isLive))
        let video = try await CatalogService.downloadMedia(wallpaper)
        let info = try await VideoInfo.load(video)
        let request = LivePhotoRequest.filling(source: video, uprightSize: info.uprightSize, duration: info.duration)
        let result = try await LivePhotoBuilder.build(request, in: URL.temporaryDirectory.appending(path: "CatalogTests-\(UUID().uuidString)", directoryHint: .isDirectory))
        _ = try await LivePhotoLoader.load(result)
    }

    @Test func centerCropFillsTheScreenAspect() {
        let target = WallpaperFormat.aspectRatio
        for size in [CGSize(width: 1080, height: 1920), CGSize(width: 1920, height: 1080), CGSize(width: 800, height: 2400)] {
            let crop = LivePhotoRequest.centerCrop(for: size)
            let croppedAspect = (crop.width * size.width) / (crop.height * size.height)
            #expect(abs(croppedAspect - target) < 0.001)
            #expect(abs(crop.midX - 0.5) < 0.001 && abs(crop.midY - 0.5) < 0.001)
        }
    }
}
