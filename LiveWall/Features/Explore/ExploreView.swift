import SwiftUI

@Observable
final class ExploreModel {
    enum State: Equatable { case loading, loaded, failed(String) }

    /// One editorial row, which See all opens as a grid.
    struct Section: Identifiable, Hashable {
        let id: String
        let title: String
        let wallpapers: [Wallpaper]
    }

    private(set) var state: State = .loading
    private(set) var wallpapers: [Wallpaper]

    init(wallpapers: [Wallpaper] = []) {
        self.wallpapers = wallpapers
    }

    /// Leads Explore as a carousel: wallpapers flagged as featured, or else the catalog's Featured category.
    var featured: [Wallpaper] {
        let flagged = wallpapers.filter(\.isFeatured)
        guard flagged.isEmpty else { return flagged }
        return wallpapers.filter { $0.category.localizedCaseInsensitiveCompare("Featured") == .orderedSame }
    }

    /// New, then live and still, then one row per category in the catalog's order. Empty rows are left out.
    func sections(now: Date = .now) -> [Section] {
        let cutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
        var seen = Set<String>()
        let categories = wallpapers.map(\.category).filter { seen.insert($0).inserted }
        let carousel = featured.map(\.id)
        let fixed = [
            Section(id: "new", title: "New this week", wallpapers: wallpapers.filter { ($0.createdDate ?? .distantPast) > cutoff }),
            Section(id: "live", title: "Live wallpapers", wallpapers: wallpapers.filter(\.isLive)),
            Section(id: "still", title: "Still wallpapers", wallpapers: wallpapers.filter { !$0.isLive }),
        ]
        let byCategory = categories.map { category in
            Section(id: "category:\(category)", title: category, wallpapers: wallpapers.filter { $0.category == category })
        }
        // A Featured category that already fills the carousel would only repeat it.
        .filter { $0.wallpapers.map(\.id) != carousel }
        return (fixed + byCategory).filter { !$0.wallpapers.isEmpty }
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

/// An opened wallpaper and the card it opened from. The same wallpaper can sit in several rows,
/// and the zoom needs the card that was actually tapped.
private struct Opened: Identifiable {
    let wallpaper: Wallpaper
    let source: String
    var id: String { source }
}

struct ExploreView: View {
    /// Waits out the launch intro, which would otherwise hide the cards arriving.
    var holdsReveal = false

    @State private var model = ExploreModel()
    @State private var opened: Opened?
    /// The carousel position in view, counting across the repeated laps; only its card plays.
    @State private var featuredPage: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    /// True while a finger is on the carousel, so auto-advance never fights a swipe.
    @State private var isTouchingCarousel = false
    @State private var isVisible = false
    /// Fast loads skip the placeholders, so they don't flash for a split second.
    @State private var showsPlaceholders = false
    /// Flips once the first catalog arrives, so the sections on screen rise in one by one; ones scrolled to later just appear.
    @State private var isRevealed = false
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
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
            .toolbar(.hidden, for: .navigationBar)
            // A navigation stack paints over the tab's background, so it carries its own.
            .background { AppBackground() }
            .navigationDestination(for: ExploreModel.Section.self) { section in
                SectionGrid(section: section, zoom: zoom) { opened = $0 }
            }
        }
        .task { await model.load() }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            showsPlaceholders = true
        }
        .onChange(of: model.state, revealIfReady)
        .onChange(of: holdsReveal, revealIfReady)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .sheet(item: $opened) { opened in
            WallpaperDetailView(wallpaper: opened.wallpaper)
                .zoomTransition(from: opened.source, in: zoom)
        }
    }

    private func revealIfReady() {
        if model.state == .loaded && !holdsReveal { isRevealed = true }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            if showsPlaceholders { ExploreSkeleton() }
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
            let featured = model.featured
            if !featured.isEmpty {
                carousel(featured)
                    .staggeredReveal(0, isRevealed: isRevealed)
            }
            ForEach(Array(model.sections().enumerated()), id: \.element.id) { index, section in
                row(section)
                    .staggeredReveal(1 + index, isRevealed: isRevealed)
            }
            Label("Touch and hold a wallpaper to preview its motion", systemImage: "hand.tap")
                .font(.labelMedium)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// Featured wallpapers like albums on a shelf: the centre card is full size, its neighbours peek in
    /// smaller and turned towards it, and swiping hands the size over smoothly. Only the centre card plays.
    private func carousel(_ featured: [Wallpaper]) -> some View {
        let count = featured.count
        // Endless: the cards repeat lap after lap, so the first always follows the last in either direction.
        // shortcut: 200 laps, not truly infinite; auto-advance recentres at the end, and nobody swipes that far.
        // VoiceOver gets a single lap, so it doesn't list every card 200 times.
        let laps = count > 1 && !voiceOver ? 200 : 1
        let total = laps * count
        // Opens on the middle card of the middle lap, so there's a neighbour on each side to swipe to.
        let start = laps / 2 * count + count / 2
        let current = min(featuredPage ?? start, total - 1)
        // Moving content is hard to follow with VoiceOver and unwanted with Reduce Motion.
        let autoAdvances = featured.count > 1 && isVisible && opened == nil && !isTouchingCarousel && !reduceMotion && !voiceOver
        return VStack(spacing: 12) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<total, id: \.self) { position in
                        let wallpaper = featured[position % count]
                        Button {
                            if position == current {
                                opened = Opened(wallpaper: wallpaper, source: "featured/\(position)")
                            } else {
                                // A side card slides to the centre first, like picking up the next album.
                                withAnimation(.smooth(duration: 0.45)) { featuredPage = position }
                            }
                        } label: {
                            FeaturedCard(
                                wallpaper: wallpaper,
                                isPlaying: isVisible && opened == nil && current == position && UIAccessibility.isVideoAutoplayEnabled
                            )
                        }
                        .buttonStyle(CardPressStyle())
                        // By position, since with two wallpapers the same one sits on both sides.
                        .zoomSource(id: "featured/\(position)", in: zoom, cornerRadius: 28)
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition(.interactive, axis: .horizontal) { card, phase in
                            // phase.value runs -1 (off to the left) … 0 (centre) … 1 (off to the right).
                            let distance = min(abs(phase.value), 1)
                            return card
                                .scaleEffect(1 - distance * 0.16)
                                // Pulls a shrunk side card back so it still peeks in beside the centre card, without covering it.
                                .offset(x: -phase.value * 24)
                                .rotation3DEffect(
                                    .degrees(reduceMotion ? 0 : -phase.value * 32),
                                    axis: (x: 0, y: 1, z: 0),
                                    perspective: 0.55
                                )
                                .opacity(1 - distance * 0.35)
                        }
                        .accessibilityIdentifier("featured-card")
                    }
                }
                .scrollTargetLayout()
            }
            // The margins shrink each card and leave room for the neighbours to peek in.
            .contentMargins(.horizontal, 56, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $featuredPage)
            .onAppear { if featuredPage == nil { featuredPage = start } }
            .tracksScrollInteraction($isTouchingCarousel)
            // Restarts on every page change, so a swipe gets a full 5 s before the next card slides in.
            .task(id: autoAdvances ? current : nil) {
                guard autoAdvances else { return }
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                if current + 1 < total {
                    withAnimation(.smooth(duration: 0.8)) { featuredPage = current + 1 }
                } else {
                    // Out of laps: jump unseen to the same card in the middle lap; the next advance slides on from there.
                    featuredPage = laps / 2 * count + current % count
                }
            }
            .scrollIndicators(.hidden)
            .fullBleed()
            if featured.count > 1 {
                HStack(spacing: 6) {
                    ForEach(featured.indices, id: \.self) { index in
                        Circle()
                            .fill(index == current % count ? Theme.textPrimary : Theme.textTertiary.opacity(0.5))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.easeOut(duration: 0.2), value: current)
                .accessibilityHidden(true)
            }
        }
    }

    private func row(_ section: ExploreModel.Section) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .typography(.headlineSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink(value: section) {
                    HStack(spacing: 2) {
                        Text("See all")
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .font(.labelLarge)
                    .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("See all \(section.title)")
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(section.wallpapers) { wallpaper in
                        CatalogCardButton(wallpaper: wallpaper, source: "\(section.id)/\(wallpaper.id)", zoom: zoom) { opened = $0 }
                            // Three cards and a peek of the fourth, so more of each row and more rows fit on screen.
                            .containerRelativeFrame(.horizontal, count: 10, span: 3, spacing: 10)
                            // Cards coming in from the right start smaller and faded, so they seem to rise from behind.
                            // Cards leaving on the left just slide away.
                            .scrollTransition(.interactive, axis: .horizontal) { card, phase in
                                let distance = reduceMotion ? 0 : min(max(phase.value, 0), 1)
                                return card
                                    .scaleEffect(1 - distance * 0.2, anchor: .leading)
                                    .opacity(1 - distance * 0.45)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .fullBleed()
        }
    }
}

/// A section's wallpapers in three columns, opened from See all. The cards are dealt in from the top.
private struct SectionGrid: View {
    let section: ExploreModel.Section
    let zoom: Namespace.ID
    let open: (Opened) -> Void

    @State private var isDealt = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(section.wallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                    CatalogCardButton(wallpaper: wallpaper, source: "grid/\(wallpaper.id)", zoom: zoom, open: open)
                        .dealtIn(index, isDealt: isDealt)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background { AppBackground() }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isDealt = true }
    }
}

/// A wallpaper card that opens on tap and, for a live one, plays while held.
private struct CatalogCardButton: View {
    let wallpaper: Wallpaper
    let source: String
    let zoom: Namespace.ID
    let open: (Opened) -> Void

    @State private var isPreviewing = false
    /// The release that ends a preview also counts as a tap, which shouldn't open the wallpaper.
    /// Marked when the preview starts, because the tap fires before the preview's end is seen.
    @State private var previewed = false

    var body: some View {
        Button {
            if previewed { previewed = false } else { open(Opened(wallpaper: wallpaper, source: source)) }
        } label: {
            CatalogCard(wallpaper: wallpaper, isPreviewing: isPreviewing)
        }
        // The button's own press, unlike an added gesture, gives way to scrolling. Stills have nothing to play.
        .buttonStyle(CardPressStyle(onHold: wallpaper.isLive ? { isPreviewing = $0 } : nil))
        .zoomSource(id: source, in: zoom, cornerRadius: 18)
        .sensoryFeedback(.impact(weight: .light), trigger: isPreviewing) { _, isOn in isOn }
        .onChange(of: isPreviewing) { _, isOn in
            if isOn {
                previewed = true
            } else {
                // A drag off the card ends the preview without a tap, so the mark can't wait for one.
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    previewed = false
                }
            }
        }
        .accessibilityIdentifier("catalog-card")
    }
}

private extension View {
    /// Lets a horizontal row scroll off the screen edges instead of stopping at the page margin.
    func fullBleed() -> some View {
        contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
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

private extension View {
    /// Reports whether the scroll view is moving under a finger or settling. iOS 17 has no scroll phases,
    /// so there it never reports touching and auto-advance can't pause mid-swipe.
    @ViewBuilder func tracksScrollInteraction(_ isInteracting: Binding<Bool>) -> some View {
        if #available(iOS 18, *) {
            onScrollPhaseChange { _, phase in isInteracting.wrappedValue = phase != .idle }
        } else {
            self
        }
    }

    func dealtIn(_ index: Int, isDealt: Bool) -> some View {
        modifier(DealtIn(index: index, isDealt: isDealt))
    }
}

/// Drops in from above with a slight tilt, one card after another, like a shuffled deck being dealt.
/// Reduce Motion keeps just the fade, all at once.
private struct DealtIn: ViewModifier {
    var index: Int
    var isDealt: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isMoving = !isDealt && !reduceMotion
        content
            .opacity(isDealt ? 1 : 0)
            .offset(y: isMoving ? -120 : 0)
            .rotationEffect(.degrees(isMoving ? (index.isMultiple(of: 2) ? -7 : 6) : 0))
            .scaleEffect(isMoving ? 0.9 : 1)
            .animation(reduceMotion
                ? .easeOut(duration: 0.25)
                // Cards past the first screenful arrive together rather than keeping the user waiting.
                : .spring(duration: 0.55, bounce: 0.22).delay(Double(min(index, 14)) * 0.045),
                value: isDealt)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(spacing: 12) {
                card(cornerRadius: 28, titleWidth: 0.5)
                    .aspectRatio(4 / 5, contentMode: .fit)
                    // The carousel's card sits inside 56 pt margins, 40 more than the page's.
                    .padding(.horizontal, 40)
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { _ in Circle().fill(Theme.placeholder).frame(width: 6, height: 6) }
                }
                .frame(maxWidth: .infinity)
            }
            ForEach(0..<2, id: \.self) { row in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Capsule().fill(Theme.placeholder).frame(width: row == 0 ? 150 : 120, height: 18).shimmer()
                        Spacer()
                        Capsule().fill(Theme.placeholder).frame(width: 60, height: 14).shimmer()
                    }
                    // Sized exactly like a loaded row (three cards and a peek, running off the edge),
                    // without pushing the page wider than the screen.
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(0..<4, id: \.self) { index in
                                card(cornerRadius: 18, titleWidth: index.isMultiple(of: 2) ? 0.7 : 0.55)
                                    .aspectRatio(9 / 16, contentMode: .fit)
                                    .containerRelativeFrame(.horizontal, count: 10, span: 3, spacing: 10)
                            }
                        }
                    }
                    .scrollDisabled(true)
                    .scrollIndicators(.hidden)
                    .fullBleed()
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
                    .overlay {
                        if let videoURL = wallpaper.videoURL { LoopingVideoView(url: videoURL, isPlaying: isPlaying) }
                    }
            }
            .overlay(alignment: .topLeading) {
                StatusPill(text: "FEATURED", dot: Theme.signalYellow, symbol: "star.fill")
                    // Glass renders flat and ignores the carousel's 3D turn, so it warped; a plain fill turns with the card.
                    .environment(\.isOnGlass, true)
                    .background(.black.opacity(0.35), in: Capsule())
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
        let length = wallpaper.durationSeconds.map { "\($0.formatted(.number.precision(.fractionLength(1))))s live wallpaper" } ?? "Still wallpaper"
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
                    .overlay {
                        if let videoURL = wallpaper.videoURL { LoopingVideoView(url: videoURL, isPlaying: isPreviewing) }
                    }
            }
            .overlay(alignment: .topLeading) {
                KindPill(wallpaper: wallpaper).padding(8)
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(wallpaper.title).typography(.labelLarge).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                    Text(wallpaper.category).font(.labelSmall).foregroundStyle(Theme.onMediaSecondary).lineLimit(1)
                }
                .mediaCaption()
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.specularRim, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            // Wallpaper tiles are dark media, so their glass pills stay dark too.
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(wallpaper.title), \(wallpaper.category)")
            .accessibilityAddTraits(.isButton)
    }
}

/// A live wallpaper's length, or STILL for one without motion.
private struct KindPill: View {
    let wallpaper: Wallpaper

    var body: some View {
        if let seconds = wallpaper.durationSeconds {
            StatusPill(text: "\(seconds.formatted(.number.precision(.fractionLength(1))))s", dot: Theme.signalYellow)
        } else {
            StatusPill(text: "STILL", symbol: "photo")
        }
    }
}
