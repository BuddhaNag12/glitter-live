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

    @Test func newThisWeekHoldsOnlyRecentWallpapers() {
        let model = ExploreModel(wallpapers: [wallpaper("A"), wallpaper("B", created: "2026-11-01T09:00:00+00:00")])
        #expect(model.newThisWeek(now: now)?.wallpapers.map(\.title) == ["B"])
        #expect(ExploreModel(wallpapers: [wallpaper("A")]).newThisWeek(now: now) == nil)
    }

    @Test func groupsCategoriesByKindInCatalogOrder() {
        let model = ExploreModel(wallpapers: [
            wallpaper("A"),
            wallpaper("B", category: "Nature", still: true),
            wallpaper("C", category: "Nature"),
            wallpaper("D", category: "Abstract", still: true),
        ])
        #expect(model.categories(live: true).map(\.title) == ["Glitter Originals", "Nature"])
        #expect(model.categories(live: true)[1].wallpapers.map(\.title) == ["C"])
        #expect(model.categories(live: false).map(\.title) == ["Nature", "Abstract"])
        #expect(ExploreModel(wallpapers: [wallpaper("A")]).categories(live: false).isEmpty)
    }

    @Test func featuredPrefersTheFlagThenTheFeaturedCategory() {
        let flagged = ExploreModel(wallpapers: [wallpaper("A", category: "Featured"), wallpaper("B", featured: true)])
        #expect(flagged.featured.map(\.title) == ["B"])

        let fallback = ExploreModel(wallpapers: [wallpaper("A", category: "Featured"), wallpaper("B")])
        #expect(fallback.featured.map(\.title) == ["A"])
        // The Featured category already fills the carousel, so it gets no row of its own.
        #expect(!fallback.categories(live: true).contains { $0.title == "Featured" })
    }
}
