import SwiftUI

@Observable
final class ExploreModel {
    enum State: Equatable { case loading, loaded, failed(String) }

    private(set) var state: State = .loading
    private(set) var wallpapers: [Wallpaper] = []
    var selectedCategory: String?

    var categories: [String] {
        var seen = Set<String>()
        return wallpapers.map(\.category).filter { seen.insert($0).inserted }
    }

    /// Leads "All" as a large, playing card; the first wallpaper in the catalog's Featured category.
    var featured: Wallpaper? {
        guard selectedCategory == nil else { return nil }
        return wallpapers.first { $0.category.localizedCaseInsensitiveCompare("Featured") == .orderedSame }
    }

    var visibleWallpapers: [Wallpaper] {
        guard let selectedCategory else { return wallpapers.filter { $0.id != featured?.id } }
        return wallpapers.filter { $0.category == selectedCategory }
    }

    func load() async {
        #if DEBUG
        if DemoLaunch.holdsLoading { try? await Task.sleep(for: .seconds(3)) }
        #endif
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
    /// Waits out the launch intro, which would otherwise hide the cards arriving.
    var holdsReveal = false

    @State private var model = ExploreModel()
    @State private var selection: Wallpaper?
    /// The card being held down to preview its motion.
    @State private var previewing: Wallpaper.ID?
    /// The release that ends a preview also counts as a tap, which shouldn't open the wallpaper.
    /// Marked when the preview starts, because the tap fires before the preview's end is seen.
    @State private var previewedCard: Wallpaper.ID?
    @State private var isVisible = false
    /// Fast loads skip the placeholders, so they don't flash for a split second.
    @State private var showsPlaceholders = false
    /// Flips once the first catalog arrives, so the cards on screen rise in one by one; cards scrolled to later just appear.
    @State private var isRevealed = false
    @Namespace private var zoom

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .animation(.easeOut(duration: 0.3), value: model.state)
            .shimmerCoordinateSpace()
            .padding(16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.load() }
        .screenHeader("Explore")
        .task { await model.load() }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            showsPlaceholders = true
        }
        .onChange(of: model.state, revealIfReady)
        .onChange(of: holdsReveal, revealIfReady)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .sensoryFeedback(.impact(weight: .light), trigger: previewing) { _, id in id != nil }
        .onChange(of: previewing) { old, new in
            if let new {
                previewedCard = new
            } else if let old {
                // A drag off the card ends the preview without a tap, so the mark can't wait for one.
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    if previewedCard == old { previewedCard = nil }
                }
            }
        }
        .sheet(item: $selection) { wallpaper in
            WallpaperDetailView(wallpaper: wallpaper)
                .zoomTransition(from: wallpaper.id, in: zoom)
        }
    }

    private func revealIfReady() {
        if model.state == .loaded && !holdsReveal { isRevealed = true }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            if showsPlaceholders { ExploreSkeleton(columns: columns) }
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
                .staggeredReveal(0, isRevealed: isRevealed)
            if let featured = model.featured {
                Button { selection = featured } label: {
                    FeaturedCard(wallpaper: featured, isPlaying: isVisible && selection == nil && UIAccessibility.isVideoAutoplayEnabled)
                }
                .buttonStyle(CardPressStyle())
                .zoomSource(id: featured.id, in: zoom, cornerRadius: 28)
                .staggeredReveal(1, isRevealed: isRevealed)
                .accessibilityIdentifier("featured-card")
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(model.visibleWallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                    Button {
                        if previewedCard == wallpaper.id { previewedCard = nil } else { selection = wallpaper }
                    } label: {
                        CatalogCard(wallpaper: wallpaper, isPreviewing: previewing == wallpaper.id)
                    }
                    // The button's own press, unlike an added gesture, gives way to scrolling.
                    .buttonStyle(CardPressStyle { isHeld in
                        if isHeld { previewing = wallpaper.id } else if previewing == wallpaper.id { previewing = nil }
                    })
                    .zoomSource(id: wallpaper.id, in: zoom, cornerRadius: 24)
                    // Row plus column, so the cards arrive in a diagonal wave like the loading sheen.
                    .staggeredReveal(2 + index / 2 + index % 2, isRevealed: isRevealed)
                    .accessibilityIdentifier("catalog-card")
                }
            }
            if !model.visibleWallpapers.isEmpty {
                Label("Touch and hold a wallpaper to preview its motion", systemImage: "hand.tap")
                    .font(.labelMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
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
        // A scroll view clips to its frame, which would cut off the glass rim and its press effect.
        .scrollClipDisabled()
        // Full bleed, so chips scroll off the screen edge instead of stopping at the page margin.
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title) { withAnimation(.spring(duration: 0.3)) { action() } }
            .buttonStyle(GlassPillButtonStyle(tint: selected ? Theme.accent : nil))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension View {
    func staggeredReveal(_ step: Int, isRevealed: Bool) -> some View {
        modifier(StaggeredReveal(step: step, isRevealed: isRevealed))
    }
}

/// Rises and fades in a beat after the step before it. Reduce Motion keeps just the fade, all at once.
private struct StaggeredReveal: ViewModifier {
    var step: Int
    var isRevealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isMoving = !isRevealed && !reduceMotion
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isMoving ? 16 : 0)
            .scaleEffect(isMoving ? 0.97 : 1)
            .animation(reduceMotion
                ? .easeOut(duration: 0.25)
                : .spring(duration: 0.5, bounce: 0.1).delay(Double(min(step, 8)) * 0.06),
                value: isRevealed)
    }
}

/// Shrinks on touch-down, so a card answers the finger before anything opens.
private struct CardPressStyle: ButtonStyle {
    /// Holding a card plays its motion until the finger lifts, like a Live Photo in Photos.
    var onHold: ((Bool) -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
            .task(id: configuration.isPressed) {
                guard let onHold else { return }
                guard configuration.isPressed else { return onHold(false) }
                try? await Task.sleep(for: .seconds(0.3))
                if !Task.isCancelled { onHold(true) }
            }
    }
}

private struct WallpaperThumbnail: View {
    let wallpaper: Wallpaper

    var body: some View {
        AsyncImage(url: wallpaper.thumbnailURL, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                AuroraView(isAnimated: false).opacity(0.35)
                    .shimmer(phase.error == nil)
            }
        }
    }
}

/// The loaded page's layout in placeholder form, so nothing jumps when the wallpapers arrive.
private struct ExploreSkeleton: View {
    let columns: [GridItem]
    private let chipWidths: [CGFloat] = [52, 92, 76, 100]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(chipWidths.indices, id: \.self) { index in
                    Capsule().fill(Theme.placeholder).frame(width: chipWidths[index], height: 40).shimmer()
                }
            }
            card(cornerRadius: 28, titleWidth: 0.5)
                .aspectRatio(4 / 5, contentMode: .fit)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    card(cornerRadius: 24, titleWidth: index.isMultiple(of: 2) ? 0.7 : 0.55)
                        .aspectRatio(9 / 16, contentMode: .fit)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading wallpapers")
    }

    /// Bars where the duration pill and caption will sit.
    private func card(cornerRadius: CGFloat, titleWidth: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape.fill(Theme.placeholder)
            .overlay(alignment: .topLeading) {
                Capsule().fill(Theme.fill).frame(width: 52, height: 24).padding(10)
            }
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(Theme.fill).frame(width: geometry.size.width * titleWidth, height: 12)
                        Capsule().fill(Theme.fill).frame(width: geometry.size.width * 0.35, height: 10)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(14)
                }
            }
            .shimmer()
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.specularRim, lineWidth: 1))
    }
}

/// The lead wallpaper, large and in motion, so Explore opens on something alive.
private struct FeaturedCard: View {
    let wallpaper: Wallpaper
    var isPlaying: Bool

    var body: some View {
        Theme.lockScreen
            .aspectRatio(4 / 5, contentMode: .fit)
            .overlay {
                WallpaperThumbnail(wallpaper: wallpaper)
                    .overlay { LoopingVideoView(url: wallpaper.videoURL, isPlaying: isPlaying) }
            }
            .overlay(alignment: .topLeading) {
                StatusPill(text: "FEATURED", dot: Theme.signalYellow, symbol: "star.fill")
                    .padding(14)
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(wallpaper.title).typography(.headlineSmall).foregroundStyle(.white).lineLimit(1)
                    Text(subtitle).font(.labelMedium.weight(.semibold)).foregroundStyle(Theme.onMediaSecondary).lineLimit(1)
                }
                .mediaCaption()
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.specularRim, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Featured: \(wallpaper.title)")
            .accessibilityAddTraits(.isButton)
    }

    private var subtitle: String {
        let length = "\(wallpaper.durationSeconds.formatted(.number.precision(.fractionLength(1))))s live wallpaper"
        guard let creator = wallpaper.creatorName else { return length }
        return "\(length) · by \(creator)"
    }
}

private struct CatalogCard: View {
    let wallpaper: Wallpaper
    var isPreviewing = false

    var body: some View {
        Theme.lockScreen
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                WallpaperThumbnail(wallpaper: wallpaper)
                    .overlay { LoopingVideoView(url: wallpaper.videoURL, isPlaying: isPreviewing) }
            }
            .overlay(alignment: .topLeading) {
                StatusPill(text: "\(wallpaper.durationSeconds.formatted(.number.precision(.fractionLength(1))))s", dot: Theme.signalYellow)
                    .padding(10)
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper.title).typography(.titleMedium).foregroundStyle(.white).lineLimit(1)
                    Text(wallpaper.category).font(.labelMedium.weight(.semibold)).foregroundStyle(Theme.onMediaSecondary).lineLimit(1)
                }
                .mediaCaption()
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.specularRim, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            // Wallpaper tiles are dark media, so their glass pills stay dark too.
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(wallpaper.title), \(wallpaper.category)")
            .accessibilityAddTraits(.isButton)
    }
}
