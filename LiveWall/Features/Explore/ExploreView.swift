import SwiftUI

@Observable
final class ExploreModel {
    enum State { case loading, loaded, failed(String) }

    private(set) var state: State = .loading
    private(set) var wallpapers: [Wallpaper] = []
    var selectedCategory: String?

    var categories: [String] {
        var seen = Set<String>()
        return wallpapers.map(\.category).filter { seen.insert($0).inserted }
    }

    var visibleWallpapers: [Wallpaper] {
        guard let selectedCategory else { return wallpapers }
        return wallpapers.filter { $0.category == selectedCategory }
    }

    func load() async {
        if wallpapers.isEmpty { state = .loading }
        do {
            wallpapers = try await CatalogService.fetchWallpapers()
            state = .loaded
        } catch {
            if wallpapers.isEmpty { state = .failed(error.localizedDescription) }
        }
    }
}

struct ExploreView: View {
    @State private var model = ExploreModel()
    @State private var selection: Wallpaper?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Explore")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.load() }
        }
        .task { await model.load() }
        .sheet(item: $selection) { wallpaper in
            WallpaperDetailView(wallpaper: wallpaper)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Theme.elevated)
                        .aspectRatio(9 / 16, contentMode: .fit)
                }
            }
            .redacted(reason: .placeholder)
            .accessibilityLabel("Loading wallpapers")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load wallpapers", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.load() } }
                    .buttonStyle(GlassPillButtonStyle(tint: Theme.accent))
            }
            .padding(.top, 60)
        case .loaded where model.wallpapers.isEmpty:
            ContentUnavailableView("New wallpapers are on the way", systemImage: "sparkles", description: Text("Check back soon."))
                .padding(.top, 60)
        case .loaded:
            categoryChips
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.visibleWallpapers) { wallpaper in
                    Button { selection = wallpaper } label: {
                        CatalogCard(wallpaper: wallpaper)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("catalog-card")
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal) {
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    chip("All", selected: model.selectedCategory == nil) { model.selectedCategory = nil }
                    ForEach(model.categories, id: \.self) { category in
                        chip(category, selected: model.selectedCategory == category) { model.selectedCategory = category }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title) { withAnimation(.spring(duration: 0.3)) { action() } }
            .buttonStyle(GlassPillButtonStyle(tint: selected ? Theme.accent : nil))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CatalogCard: View {
    let wallpaper: Wallpaper

    var body: some View {
        Theme.lockScreen
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                AsyncImage(url: wallpaper.thumbnailURL, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        AuroraView().opacity(0.35)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                StatusPill(text: "\(wallpaper.durationSeconds.formatted(.number.precision(.fractionLength(1))))s", dot: Theme.signalYellow)
                    .padding(10)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper.title).font(.titleMedium).foregroundStyle(.white).lineLimit(1)
                    Text(wallpaper.category).font(.labelMedium).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.specularRim, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            // Wallpaper tiles are dark media, so their glass captions stay dark too.
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(wallpaper.title), \(wallpaper.category)")
            .accessibilityAddTraits(.isButton)
    }
}
