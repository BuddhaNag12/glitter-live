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

    @Test func buildsRowsInOrderAndLeavesOutEmptyOnes() {
        let model = ExploreModel(wallpapers: [
            wallpaper("A"),
            wallpaper("B", category: "Nature", still: true, created: "2026-11-01T09:00:00+00:00"),
            wallpaper("C", category: "Nature"),
        ])
        let sections = model.sections(now: now)
        #expect(sections.map(\.title) == ["New this week", "Glitter Originals", "Nature"])
        #expect(sections[0].wallpapers.map(\.title) == ["B"])
        #expect(sections[2].wallpapers.map(\.title) == ["B", "C"])

        let oldOnly = ExploreModel(wallpapers: [wallpaper("A")]).sections(now: now)
        #expect(oldOnly.map(\.title) == ["Glitter Originals"])
    }

    @Test func filtersEveryRowAndTheCarouselByKind() {
        let model = ExploreModel(wallpapers: [
            wallpaper("A", featured: true),
            wallpaper("B", category: "Nature", still: true, featured: true),
            wallpaper("C", category: "Nature"),
            wallpaper("D"),
            wallpaper("E", category: "Nature", still: true),
        ])
        #expect(model.sections(.live, now: now).map(\.title) == ["Glitter Originals", "Nature"])
        #expect(model.sections(.live, now: now)[1].wallpapers.map(\.title) == ["C"])
        #expect(model.sections(.stills, now: now).map(\.title) == ["Nature"])
        #expect(model.featured(.live).map(\.title) == ["A"])
        #expect(model.featured(.stills).map(\.title) == ["B"])
        #expect(model.featured().map(\.title) == ["A", "B"])
    }

    @Test func featuredPrefersTheFlagThenTheFeaturedCategory() {
        let flagged = ExploreModel(wallpapers: [wallpaper("A", category: "Featured"), wallpaper("B", featured: true)])
        #expect(flagged.featured().map(\.title) == ["B"])

        let fallback = ExploreModel(wallpapers: [wallpaper("A", category: "Featured"), wallpaper("B")])
        #expect(fallback.featured().map(\.title) == ["A"])
        // The Featured category already fills the carousel, so it gets no row of its own.
        #expect(!fallback.sections(now: now).contains { $0.title == "Featured" })
    }
}
