import Foundation
import Testing
@testable import LiveWall

struct ExploreModelTests {
    private let now = try! Date.ISO8601FormatStyle().parse("2026-11-07T12:00:00Z")

    private func wallpaper(_ title: String, category: String = "Glitter Originals", still: Bool = false, featured: Bool = false, created: String = "2026-09-30T11:00:39.530395+00:00") -> Wallpaper {
        Wallpaper(
            id: UUID(), kind: still ? .still : .live, title: title, category: category,
            videoPath: still ? nil : "videos/\(title).mp4", imagePath: still ? "images/\(title).jpg" : nil,
            thumbnailPath: "thumbnails/\(title).jpg", durationSeconds: still ? nil : 4, width: 1080, height: 1920,
            creatorName: nil, creatorURL: nil, isFeatured: featured, createdAt: created
        )
    }

    @Test func groupsLiveAndStillByCategoryInCatalogOrder() {
        let model = ExploreModel(wallpapers: [
            wallpaper("A"),
            wallpaper("B", category: "Nature", still: true),
            wallpaper("C", category: "Nature"),
            wallpaper("D", category: "Abstract", still: true),
        ])
        #expect(model.categories.map(\.title) == ["Glitter Originals", "Nature", "Abstract"])
        #expect(model.categories[1].wallpapers.map(\.title) == ["B", "C"])
    }

    @Test func featuredPrefersTheFlagThenTheFeaturedCategory() {
        let flagged = ExploreModel(wallpapers: [wallpaper("A", category: "Featured"), wallpaper("B", featured: true)])
        #expect(flagged.featured.map(\.title) == ["B"])

        let fallback = ExploreModel(wallpapers: [wallpaper("A", category: "Featured"), wallpaper("B")])
        #expect(fallback.featured.map(\.title) == ["A"])
        // The Featured category already fills the carousel, so it gets no row of its own.
        #expect(!fallback.categories.contains { $0.title == "Featured" })
    }
}
