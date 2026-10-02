import SwiftUI

/// Apps can't set the wallpaper themselves, so this walks the user through the Photos flow.
struct SetWallpaperGuideView: View {
    /// Stills skip the Live Photo step and the advice about motion.
    var isLive = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Set as Wallpaper")
                            .typography(.headlineLarge)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Only Photos can set a wallpaper.")
                            .typography(.bodyMedium)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(CircleIconButtonStyle(size: 36))
                        .accessibilityLabel("Close")
                }

                WallpaperSteps(isLive: isLive)

                if isLive {
                    VStack(alignment: .leading, spacing: 14) {
                        GuideNote(symbol: "livephoto", text: "Plays each time you wake your iPhone.")
                        GuideNote(symbol: "bolt.slash", text: "Not moving? Turn off Low Power Mode.")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(.surface, cornerRadius: 24)
                }
            }
            .padding(.horizontal, 20)
            // Clears the grab bar, so the title never sits under it.
            .padding(.top, 32)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button {
                if let url = URL(string: "photos-redirect://") { openURL(url) }
            } label: {
                Label("Open Photos", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(KineticButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        // Sized to the content, so no empty gap sits above the button; larger text gets the full height.
        .presentationDetents(dynamicTypeSize > .xLarge ? [.large] : [.height(isLive ? 590 : 470), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground { AppBackground() }
    }
}

/// The Photos steps for setting a wallpaper, shared by the guide and onboarding.
struct WallpaperSteps: View {
    var isLive = true
    /// Onboarding walks through the steps, lighting each one in turn.
    var highlightsInTurn = false

    @State private var current = 0
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var steps: [(symbol: String, text: String)] {
        [
            ("photo.on.rectangle", isLive ? "Open the Live Photo in Photos." : "Open the wallpaper in Photos."),
            ("square.and.arrow.up", "Tap Share → Use as Wallpaper."),
            isLive
                ? ("livephoto", "Make sure Live Photo is on.")
                : ("arrow.up.left.and.arrow.down.right", "Pinch to adjust the framing."),
            ("checkmark.circle", "Tap Add → Set as Wallpaper Pair."),
        ]
    }

    var body: some View {
        VStack(spacing: highlightsInTurn ? 4 : 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let isLit = !highlightsInTurn || index == current
                HStack(spacing: 14) {
                    Text("\(index + 1)")
                        .font(.labelLarge)
                        .monospacedDigit()
                        .foregroundStyle(isLit ? Theme.onAccent : Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(isLit ? AnyShapeStyle(Theme.accentFill) : AnyShapeStyle(Theme.fill), in: Circle())
                    Text(step.text)
                        .typography(.bodyMedium)
                        .foregroundStyle(isLit ? Theme.textPrimary : Theme.textSecondary)
                        // One line each, shrinking a little on narrow phones; accessibility sizes wrap instead.
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: step.symbol)
                        .scaledIcon(size: 17, weight: .medium, frame: 28)
                        .foregroundStyle(isLit ? Theme.accent : Theme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background {
                    if highlightsInTurn && index == current {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.accent.opacity(0.12))
                            .matchedGeometryEffect(id: "highlight", in: highlight)
                    }
                }
                if !highlightsInTurn && index < steps.count - 1 {
                    Divider().overlay(Theme.stroke).padding(.leading, 58)
                }
            }
        }
        .padding(highlightsInTurn ? 6 : 2)
        .glass(.surface, cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .task(id: highlightsInTurn) {
            guard highlightsInTurn else { return }
            current = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.15)) {
                    current = (current + 1) % steps.count
                }
            }
        }
    }
}

private struct GuideNote: View {
    let symbol: String
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // A fixed width, so both notes' text starts at the same edge whatever the symbol's shape.
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(text)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.85)
        }
        .typography(.bodyMedium)
    }
}
