import SwiftUI

/// Apps can't set the wallpaper themselves, so this walks the user through the Photos flow.
struct SetWallpaperGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let steps: [(symbol: String, text: String)] = [
        ("photo.on.rectangle", "Open Photos and find the Live Photo you just saved."),
        ("square.and.arrow.up", "Tap Share, then choose Use as Wallpaper."),
        ("livephoto", "Make sure the Live Photo button in the bottom corner is on."),
        ("checkmark.circle", "Tap Add, then Set as Wallpaper Pair."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Set as Wallpaper").font(.headlineLarge).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(CircleIconButtonStyle())
                    .accessibilityLabel("Close")
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: step.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.cyan)
                            .frame(width: 40, height: 40)
                            .background(Theme.cyan.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Step \(index + 1)").font(.labelSmall).tracking(0.6).foregroundStyle(Theme.textTertiary)
                            Text(step.text).font(.bodyMedium).foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }
            .padding(18)
            .glass(.surface, cornerRadius: 22)

            Text("Your wallpaper moves briefly when you wake your iPhone.")
                .font(.labelMedium)
                .foregroundStyle(Theme.textSecondary)

            Button {
                if let url = URL(string: "photos-redirect://") { openURL(url) }
            } label: {
                Label("Open Photos", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(KineticButtonStyle())
        }
        .padding(20)
        .presentationBackground { AppBackground() }
    }
}
