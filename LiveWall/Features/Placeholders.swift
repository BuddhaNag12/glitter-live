import SwiftUI

/// Explore teaser until the curated catalog backend exists.
struct ExploreComingSoonView: View {
    private let categories: [(name: String, colors: [Color])] = [
        ("Cyberpunk", [WallpaperPalette.rose, WallpaperPalette.violet, WallpaperPalette.sky]),
        ("Anime Glow", [WallpaperPalette.violet, WallpaperPalette.rose, WallpaperPalette.amber]),
        ("Liquid Chrome", [WallpaperPalette.sky, .white, WallpaperPalette.indigo]),
        ("Cosmic", [WallpaperPalette.indigo, WallpaperPalette.blue, WallpaperPalette.teal]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Explore")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TeaserBanner(
                        symbol: "sparkles",
                        title: "Curated live wallpapers",
                        message: "Hand-picked motion wallpapers you can save in one tap are on the way."
                    )
                    Text("Coming collections")
                        .font(.headlineSmall)
                        .foregroundStyle(Theme.textPrimary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(categories, id: \.name) { category in
                            WallpaperTeaserCard(title: category.name, colors: category.colors)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// Create teaser until AI generation is wired up.
struct CreateComingSoonView: View {
    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Create")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TeaserBanner(
                        symbol: "wand.and.stars",
                        title: "AI Live Generator",
                        message: "Describe a scene or animate a photo, and AI turns it into a live wallpaper. Free to use, supported by ads."
                    )
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Motion Synthesis Prompt", systemImage: "text.bubble")
                            .font(.titleMedium)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Bioluminescent koi fish swimming through liquid starlight, slow shimmering ripples…")
                            .font(.bodyLarge)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        HStack(spacing: 10) {
                            StatusPill(text: "TEXT TO LIVE", symbol: "text.cursor")
                            StatusPill(text: "ANIMATE PHOTO", dot: Theme.slate, symbol: "photo")
                        }
                    }
                    .padding(18)
                    .glass(.floating, cornerRadius: 28)
                    .opacity(0.8)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct LibraryEmptyView: View {
    var onConvert: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Library")
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text("No wallpapers yet").font(.headlineSmall).foregroundStyle(Theme.textPrimary)
                Text("Every live wallpaper you convert is kept here, so you can preview it, save it again, or set it later.")
                    .font(.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button(action: onConvert) {
                    Label("Convert a Video", systemImage: "livephoto")
                }
                .buttonStyle(GlassPillButtonStyle(tint: Theme.accent))
                .padding(.top, 4)
            }
            .padding(26)
            .glass(.floating, cornerRadius: 30)
            .padding(16)
            Spacer()
            Spacer()
        }
    }
}

private struct TeaserBanner: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 46, height: 46)
                .liquidGlass(in: Circle(), tint: Theme.accent.opacity(0.2))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.titleMedium).foregroundStyle(Theme.textPrimary)
                    StatusPill(text: "SOON", dot: Theme.signalYellow)
                }
                Text(message).font(.bodyMedium).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.floating, cornerRadius: 26)
    }
}

private struct WallpaperTeaserCard: View {
    let title: String
    let colors: [Color]

    var body: some View {
        AuroraView(colors: colors)
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.titleMedium).foregroundStyle(.white)
                    Text("Coming soon").font(.labelMedium).foregroundStyle(.white.opacity(0.7))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.specularRim, lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}
