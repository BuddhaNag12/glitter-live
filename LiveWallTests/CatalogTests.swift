import CoreGraphics
import Foundation
import Testing
@testable import LiveWall

struct CatalogTests {
    @Test func decodesCatalogRowsAndBuildsPublicURLs() throws {
        let json = """
        [{"id":"09829bfe-fe0e-4167-939e-fcccbeb19b41","title":"Silver Shimmer","category":"Glitter Originals",
          "video_path":"videos/09829bfe.mp4","thumbnail_path":"thumbnails/09829bfe.jpg","duration_seconds":4,
          "width":1080,"height":1920,"creator_name":"Glitter Live","creator_url":null}]
        """
        let wallpapers = try JSONDecoder().decode([Wallpaper].self, from: Data(json.utf8))
        let wallpaper = try #require(wallpapers.first)
        #expect(wallpaper.title == "Silver Shimmer")
        #expect(wallpaper.creatorURL == nil)
        #expect(wallpaper.videoURL.absoluteString == "https://jusrioirjfpaocgmsbbv.supabase.co/storage/v1/object/public/wallpapers/videos/09829bfe.mp4")
    }

    /// Hits the live catalog: downloads the first wallpaper and builds a Live Photo from it, without saving.
    @Test(.timeLimit(.minutes(1))) func buildsALivePhotoFromTheLiveCatalog() async throws {
        let wallpaper = try #require(try await CatalogService.fetchWallpapers().first)
        let video = try await CatalogService.downloadVideo(wallpaper)
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
