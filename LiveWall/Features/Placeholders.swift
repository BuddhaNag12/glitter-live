import SwiftUI

/// Create teaser until AI generation is wired up.
struct CreateComingSoonView: View {
    var body: some View {
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
        .screenHeader("Create")
    }
}

struct LibraryEmptyView: View {
    var onConvert: () -> Void

    var body: some View {
        VStack(spacing: 0) {
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
        .screenHeader("Library")
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
