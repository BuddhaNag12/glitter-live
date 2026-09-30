import Photos
import SwiftUI

enum OnboardingState {
    static let completedKey = "hasCompletedOnboarding"
}

/// First-launch introduction.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var step = 0
    private let titles = ["Welcome", "How It Works", "Setup"]

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $step) {
                WelcomePage().tag(0)
                HowItWorksPage().tag(1)
                SetupPage().tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(duration: 0.35), value: step)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .background { AppBackground() }
        .sensoryFeedback(.selection, trigger: step)
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                Button { step -= 1 } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(CircleIconButtonStyle(size: 40))
                    .opacity(step > 0 ? 1 : 0)
                    .disabled(step == 0)
                    .accessibilityLabel("Back")
                Text(titles[step])
                    .font(.headlineSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.opacity)
                Spacer()
                if step < 2 {
                    Button("Skip", action: onFinish)
                        .font(.titleMedium)
                        .foregroundStyle(Theme.accent)
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index <= step ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.border))
                        .frame(width: index == step ? 28 : 10, height: 6)
                }
                Spacer()
                Text("STEP \(step + 1) OF 3")
                    .font(.labelSmall)
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of 3")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        // Swiping between pages changes the step without an animation, so the header animates itself.
        .animation(.spring(duration: 0.35), value: step)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                if step < 2 { step += 1 } else { onFinish() }
            } label: {
                Label(step < 2 ? "Continue" : "Start Creating", systemImage: "arrow.right")
                    .labelStyle(TrailingIcon())
            }
            .buttonStyle(KineticButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [Theme.background.opacity(0), Theme.background.opacity(0.95)], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        OnboardingPage {
            StatusPill(text: "LOCK SCREEN MOTION")
            Text("Welcome to Glitter Live")
                .font(.displayLarge)
                .tracking(-0.8)
                .foregroundStyle(Theme.textPrimary)
            Text("Turn your Lock Screen into a moving gallery. Your wallpaper comes alive every time you wake your iPhone.")
                .font(.bodyLarge)
                .foregroundStyle(Theme.textSecondary)

            DeviceFrame {
                AuroraView().overlay { LockScreenOverlay() }
            }
            .frame(width: 190)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            GlassGroup(spacing: 8) {
                FlowChips(items: [
                    ("sparkles", "Moves when you wake"),
                    ("livephoto", "Real Live Photos"),
                    ("checkmark.seal", "Free, no watermark"),
                ])
            }

            FeatureList(rows: [
                .init(symbol: "livephoto", title: "Video to Live Wallpaper", detail: "Trim any video into a Lock Screen wallpaper in seconds."),
                FeatureFlags.aiGeneration
                    ? .init(symbol: "wand.and.stars", title: "AI Generator", detail: "Describe a scene or animate a photo, and AI brings it to life.", badge: "SOON")
                    : .init(symbol: "sparkles", title: "Curated Wallpapers", detail: "Browse hand-picked live wallpapers and save one in a tap."),
            ])
        }
    }
}

private struct HowItWorksPage: View {
    var body: some View {
        OnboardingPage(alignment: .center) {
            Text("Convert Any Video in Seconds")
                .font(.headlineLarge)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Pick a 1–3 second moment, frame it around the clock, and choose the photo shown while your iPhone is locked.")
                .font(.bodyMedium)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            DeviceFrame {
                AuroraView(colors: [WallpaperPalette.sky, Color(hex: 0x1E3A8A), WallpaperPalette.indigo])
                    .overlay { LockScreenOverlay(showsMotionBadge: true) }
            }
            .frame(width: 170)
            .padding(.vertical, 4)

            TrimPreviewCard()

            FeatureList(rows: [
                .init(symbol: "timeline.selection", title: "Precise Trimming", detail: "Drag the handles to pick exactly the moment you want."),
                .init(symbol: "photo", title: "Sharp Cover Photo", detail: "Choose the frame your Lock Screen shows while asleep, at full screen resolution."),
                .init(symbol: "lock.shield", title: "Privacy First", detail: "Glitter Live only asks to add photos. It never reads your library."),
            ])
        }
    }
}

private struct SetupPage: View {
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

    var body: some View {
        OnboardingPage(alignment: .center) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 96, height: 96)
                    .liquidGlass(in: Circle(), tint: Theme.accent.opacity(0.18))
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.accentFill, in: Circle())
                    .offset(x: 4, y: -4)
            }
            .padding(.top, 8)

            Text("You're All Set")
                .font(.displayLarge)
                .tracking(-0.8)
                .foregroundStyle(Theme.textPrimary)
            Text("Pick any video and make your first live wallpaper in seconds.")
                .font(.bodyLarge)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            permissionCard

            VStack(alignment: .leading, spacing: 14) {
                Label("What's included", systemImage: "star")
                    .font(.headlineSmall)
                    .foregroundStyle(Theme.textPrimary)
                IncludedRow(symbol: "infinity", title: "Unlimited conversions", detail: "Turn as many videos into live wallpapers as you like.")
                IncludedRow(symbol: "photo.on.rectangle.angled", title: "Your Library", detail: "Every wallpaper you make is kept, ready to save or set again.")
                if FeatureFlags.aiGeneration {
                    IncludedRow(symbol: "wand.and.stars", title: "AI Generator, coming soon", detail: "Free to use, supported by short ads.")
                } else {
                    IncludedRow(symbol: "sparkles", title: "Curated wallpapers", detail: "Hand-picked live wallpapers in Explore, saved in one tap.")
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(.floating, cornerRadius: 28)
        }
    }

    private var permissionCard: some View {
        let granted = status == .authorized || status == .limited
        return HStack(spacing: 14) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
                .frame(width: 46, height: 46)
                .liquidGlass(in: Circle(), tint: Theme.accent.opacity(0.18))
            VStack(alignment: .leading, spacing: 3) {
                Text("Save to Photos").font(.titleMedium).foregroundStyle(Theme.textPrimary)
                Text(status == .notDetermined
                     ? "Asked the first time you save a wallpaper. Glitter Live can't see your other photos."
                     : "Needed to add your wallpapers to Photos. Glitter Live can't see your other photos.")
                    .font(.labelMedium)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if granted {
                Label("Allowed", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accentFill, in: Circle())
                    .accessibilityLabel("Allowed")
            } else if status != .notDetermined {
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(GlassPillButtonStyle(tint: Theme.signalYellow))
            }
        }
        .padding(16)
        .glass(.surface, cornerRadius: 24)
    }
}

// MARK: - Building blocks

private struct OnboardingPage<Content: View>: View {
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: alignment, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

private struct FeatureList: View {
    struct Row: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var badge: String?
        var id: String { title }
    }

    let rows: [Row]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(row.title).font(.titleMedium).foregroundStyle(Theme.textPrimary)
                            if let badge = row.badge {
                                Text(badge)
                                    .font(.labelSmall)
                                    .tracking(0.8)
                                    .foregroundStyle(Theme.signalYellow)
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(Theme.signalYellow.opacity(0.14), in: Capsule())
                            }
                        }
                        Text(row.detail).font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                if row.id != rows.last?.id {
                    Divider().overlay(Theme.stroke).padding(.horizontal, 16)
                }
            }
        }
        .glass(.floating, cornerRadius: 26)
    }
}

private struct FlowChips: View {
    let items: [(symbol: String, text: String)]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { chips(items.prefix(2)) }
                HStack(spacing: 8) { chips(items.dropFirst(2)) }
            }
        }
    }

    private var chips: some View { chips(items[...]) }

    private func chips(_ slice: ArraySlice<(symbol: String, text: String)>) -> some View {
        ForEach(slice, id: \.text) { item in
            Label(item.text, systemImage: item.symbol)
                .font(.labelMedium.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .liquidGlass(in: Capsule())
        }
    }
}

private struct TrimPreviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Trim & Key Frame", systemImage: "film")
                    .font(.titleMedium)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Target: \(Text("2.4 s").foregroundStyle(Theme.accent))")
                    .font(.labelMedium.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .liquidGlass(in: Capsule())
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    AuroraView().opacity(0.5)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.signalYellow, lineWidth: 3)
                        .frame(width: width * 0.62)
                        .overlay(alignment: .leading) { handle }
                        .overlay(alignment: .trailing) { handle }
                        .offset(x: width * 0.12)
                    VStack(spacing: 0) {
                        Circle().fill(Theme.accent).frame(width: 10, height: 10)
                        Rectangle().fill(.white).frame(width: 2)
                    }
                    .offset(x: width * 0.42)
                }
            }
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .glass(.floating, cornerRadius: 24)
        .accessibilityHidden(true)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.signalYellow)
            .frame(width: 12)
    }
}

private struct IncludedRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.titleMedium).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.labelMedium).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}
