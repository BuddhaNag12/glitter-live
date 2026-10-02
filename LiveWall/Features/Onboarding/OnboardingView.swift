import Photos
import SwiftUI

enum OnboardingState {
    static let completedKey = "hasCompletedOnboarding"
}

/// First-launch introduction: what the app does, the ways to make a wallpaper, how to set one, and what's free.
struct OnboardingView: View {
    /// The launch intro is still playing on top, so the first page waits to animate in.
    var holdsReveal = false
    var onFinish: () -> Void

    @State private var page: Int? = 0
    private static let pageCount = 4

    private var step: Int { page ?? 0 }
    private var isLastStep: Bool { step == Self.pageCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            // A paging scroll view rather than a page-style TabView, which clips its pages at the footer
            // instead of letting them scroll underneath it. Not lazy: Continue scrolls to a page by id,
            // which silently fails if that page hasn't been built yet.
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    WelcomePage(isActive: step == 0 && !holdsReveal).containerRelativeFrame(.horizontal).id(0)
                    WaysPage(isActive: step == 1).containerRelativeFrame(.horizontal).id(1)
                    SetUpPage(isActive: step == 2).containerRelativeFrame(.horizontal).id(2)
                    ReadyPage(isActive: step == 3).containerRelativeFrame(.horizontal).id(3)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .background { AppBackground(twinkles: false) }
        .sensoryFeedback(.selection, trigger: step)
    }

    private func go(to newStep: Int) {
        withAnimation(.spring(duration: 0.4)) { page = newStep }
    }

    /// Back and Skip get the same minimum width, so the progress dots sit in the center.
    private var header: some View {
        HStack {
            Button { go(to: step - 1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(CircleIconButtonStyle(size: 40))
                .opacity(step > 0 ? 1 : 0)
                .disabled(step == 0)
                .accessibilityLabel("Back")
                .frame(minWidth: 64, alignment: .leading)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<Self.pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.border))
                        .frame(width: index == step ? 28 : 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of \(Self.pageCount)")
            Spacer()
            Button("Skip", action: onFinish)
                .typography(.titleMedium)
                .foregroundStyle(Theme.accent)
                .fixedSize()
                .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                .opacity(isLastStep ? 0 : 1)
                .disabled(isLastStep)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        // Swiping between pages changes the step without an animation, so the header animates itself.
        .animation(.spring(duration: 0.35), value: step)
    }

    private var footer: some View {
        Button {
            if isLastStep { onFinish() } else { go(to: step + 1) }
        } label: {
            Label(isLastStep ? "Start Creating" : "Continue", systemImage: isLastStep ? "sparkles" : "arrow.right")
                .labelStyle(TrailingIcon())
                .contentTransition(.interpolate)
        }
        .buttonStyle(KineticButtonStyle())
        .animation(.spring(duration: 0.35), value: isLastStep)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            // Pages scroll underneath, so the lower half is solid and nothing shows through beside the button.
            LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    let isActive: Bool
    @State private var isShown = false

    var body: some View {
        OnboardingPage { isShort in
            WakingPhone(isAnimating: isActive)
                .frame(width: isShort ? 112 : 168)
                .padding(.bottom, 6)
                .reveal(isShown, order: 0)
            PageTitle("Welcome to Glitter Live", detail: "Your Lock Screen, alive. Your wallpaper moves every time you wake your iPhone.")
                .reveal(isShown, order: 1)
            FlowChips(items: [
                ("sparkles", "Moves when you wake"),
                ("livephoto", "Real Live Photos"),
                ("checkmark.seal", "No watermark"),
            ])
            .reveal(isShown, order: 2)
        }
        .onChange(of: isActive, initial: true) { _, active in if active { isShown = true } }
    }
}

private struct WaysPage: View {
    let isActive: Bool
    @State private var isShown = false

    var body: some View {
        OnboardingPage { isShort in
            PageTitle(
                "Make One Your Way",
                detail: FeatureFlags.aiGeneration
                    ? "Start from the gallery, any video, or a few words."
                    : "Start from the gallery or any video you have."
            )
            .reveal(isShown, order: 0)
            if !isShort {
                TrimPreviewCard(isAnimating: isActive)
                    .reveal(isShown, order: 1)
            }
            WayRow(symbol: "sparkles", title: "Explore", detail: "Hand-picked live wallpapers, saved in a tap.")
                .reveal(isShown, order: 2)
            WayRow(symbol: "livephoto", title: "Convert a video", detail: "From Photos, Files, a link, or Share in another app.")
                .reveal(isShown, order: 3)
            if FeatureFlags.aiGeneration {
                WayRow(symbol: "wand.and.stars", title: "Create with AI", detail: "Describe a scene, then add motion on your iPhone.")
                    .reveal(isShown, order: 4)
            }
        }
        .onChange(of: isActive, initial: true) { _, active in if active { isShown = true } }
    }
}

private struct SetUpPage: View {
    let isActive: Bool
    @State private var isShown = false

    var body: some View {
        OnboardingPage { isShort in
            if !isShort {
                HeroIcon(symbol: "photo.on.rectangle.angled", isShown: isShown)
                    .reveal(isShown, order: 0)
            }
            PageTitle("Set It From Photos", detail: "Only Photos can set a wallpaper, so it takes four quick taps. You'll find these steps in Settings too.")
                .reveal(isShown, order: 1)
            WallpaperSteps(highlightsInTurn: isActive)
                .reveal(isShown, order: 2)
        }
        .onChange(of: isActive, initial: true) { _, active in if active { isShown = true } }
    }
}

private struct ReadyPage: View {
    let isActive: Bool
    @State private var isShown = false
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

    var body: some View {
        OnboardingPage { isShort in
            if !isShort {
                HeroIcon(symbol: "checkmark.seal.fill", badge: "bolt.fill", isShown: isShown)
                    .reveal(isShown, order: 0)
            }
            PageTitle("You're All Set", detail: "Pick a video or a wallpaper and make your first one in seconds.")
                .reveal(isShown, order: 1)
            permissionCard
                .reveal(isShown, order: 2)
            includedCard
                .reveal(isShown, order: 3)
        }
        .onChange(of: isActive, initial: true) { _, active in if active { isShown = true } }
    }

    private var includedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What's included")
                .typography(.titleMedium)
                .foregroundStyle(Theme.textPrimary)
            if FeatureFlags.conversionLimits {
                IncludedRow(symbol: "gift", title: "\(ConversionAllowance.freeConversions) free conversions", detail: "Then a short ad for each, or unlock unlimited once.")
            } else {
                IncludedRow(symbol: "infinity", title: "Free conversions", detail: "Turn as many videos into live wallpapers as you like.")
            }
            if FeatureFlags.aiGeneration {
                IncludedRow(symbol: "wand.and.stars", title: "AI Generator", detail: "\(GenerationAllowance.freeGenerations) free generations, then free with a short ad.")
            }
            IncludedRow(symbol: "photo.on.rectangle.angled", title: "Your Library", detail: "Everything you make is kept, ready to save or set again.")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.floating, cornerRadius: 26)
    }

    private var permissionCard: some View {
        let granted = status == .authorized || status == .limited
        return HStack(spacing: 14) {
            Image(systemName: "photo.badge.plus")
                .scaledIcon(size: 20, frame: 46)
                .foregroundStyle(Theme.accent)
                .liquidGlass(in: Circle(), tint: Theme.accent.opacity(0.18))
            VStack(alignment: .leading, spacing: 3) {
                Text("Save to Photos").typography(.titleMedium).foregroundStyle(Theme.textPrimary)
                Text(status == .notDetermined
                     ? "Asked the first time you save. Glitter Live can't see your other photos."
                     : "Needed to add your wallpapers to Photos. Glitter Live can't see your other photos.")
                    .font(.labelMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if granted {
                Image(systemName: "checkmark")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.surface, cornerRadius: 24)
    }
}

// MARK: - Building blocks

/// One screen per page: content is centered vertically and only scrolls when large text needs it.
/// Short screens such as the iPhone SE get told so, and leave out decoration to keep everything in view.
private struct OnboardingPage<Content: View>: View {
    @ViewBuilder var content: (_ isShort: Bool) -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    content(geometry.size.height < 560)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }
}

private struct PageTitle: View {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .typography(.headlineLarge)
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .typography(.bodyLarge)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

/// Fades and rises into place, one element after another, the first time a page appears.
private struct Reveal: ViewModifier {
    let isShown: Bool
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 20)
            .animation(.spring(duration: 0.55, bounce: 0.2).delay(0.05 * Double(order)), value: isShown)
    }
}

private extension View {
    func reveal(_ isShown: Bool, order: Int) -> some View {
        modifier(Reveal(isShown: isShown, order: order))
    }
}

/// A Lock Screen that keeps waking up: dark and still, then bright and moving, like the real thing.
private struct WakingPhone: View {
    let isAnimating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion || !isAnimating {
            phone(awake: true)
        } else {
            PhaseAnimator([false, true]) { awake in
                phone(awake: awake)
            } animation: { awake in
                awake ? .spring(duration: 0.7, bounce: 0.25).delay(0.9) : .easeIn(duration: 0.6).delay(2.6)
            }
        }
    }

    private func phone(awake: Bool) -> some View {
        DeviceFrame {
            AuroraView(isAnimated: awake)
                .overlay { LockScreenOverlay(showsMotionBadge: awake) }
                .brightness(awake ? 0 : -0.55)
                .saturation(awake ? 1 : 0.4)
        }
        .scaleEffect(awake ? 1 : 0.95)
        .background {
            Circle()
                .fill(Theme.glowPrimary)
                .blur(radius: 50)
                .scaleEffect(awake ? 1.2 : 0.6)
                .opacity(awake ? 1 : 0.3)
        }
        .accessibilityHidden(true)
    }
}

private struct HeroIcon: View {
    let symbol: String
    var badge: String?
    let isShown: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce, value: isShown)
                .frame(width: 92, height: 92)
                .liquidGlass(in: Circle(), tint: Theme.accent.opacity(0.18))
            if let badge {
                Image(systemName: badge)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.accentFill, in: Circle())
                    .offset(x: 4, y: -4)
                    .scaleEffect(isShown ? 1 : 0.2)
                    .animation(.spring(duration: 0.5, bounce: 0.5).delay(0.35), value: isShown)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct WayRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .scaledIcon(size: 18, weight: .medium, frame: 44)
                .foregroundStyle(Theme.accent)
                .liquidGlass(in: Circle(), tint: Theme.accent.opacity(0.14))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).typography(.titleMedium).foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .typography(.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.floating, cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}

private struct FlowChips: View {
    let items: [(symbol: String, text: String)]

    var body: some View {
        CenteredFlow(spacing: 8) {
            ForEach(items, id: \.text) { item in
                Label(item.text, systemImage: item.symbol)
                    .font(.labelMedium.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .liquidGlass(in: Capsule())
            }
        }
    }
}

/// Lays chips out in centered rows, starting a new row only when the next chip doesn't fit.
private struct CenteredFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.midX - row.width / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if var last = rows.last, last.width + spacing + size.width <= width {
                last.indices.append(index)
                last.width += spacing + size.width
                last.height = max(last.height, size.height)
                rows[rows.count - 1] = last
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}

/// A miniature Trim Studio whose playhead keeps sweeping through the chosen moment.
private struct TrimPreviewCard: View {
    let isAnimating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let clipStart = 0.14
    private let clipWidth = 0.58

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Trim the moment", systemImage: "film")
                    .typography(.titleMedium)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("1–3 s")
                    .font(.labelMedium.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .liquidGlass(in: Capsule())
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    AuroraView().opacity(0.5)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.trimHandle, lineWidth: 3)
                        .frame(width: width * clipWidth)
                        .overlay(alignment: .leading) { handle }
                        .overlay(alignment: .trailing) { handle }
                        .offset(x: width * clipStart)
                    if reduceMotion || !isAnimating {
                        playhead.offset(x: width * (clipStart + clipWidth * 0.45))
                    } else {
                        PhaseAnimator([false, true]) { atEnd in
                            playhead.offset(x: width * (clipStart + 0.03 + (atEnd ? clipWidth - 0.06 : 0)))
                        } animation: { atEnd in
                            atEnd ? .linear(duration: 1.6) : .easeOut(duration: 0.25).delay(0.3)
                        }
                    }
                }
            }
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .glass(.floating, cornerRadius: 24)
        .accessibilityHidden(true)
    }

    private var playhead: some View {
        VStack(spacing: 0) {
            Circle().fill(Theme.accent).frame(width: 10, height: 10)
            Rectangle().fill(.white).frame(width: 2)
        }
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.trimHandle)
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
                .scaledIcon(size: 16, weight: .semibold, frame: 38)
                .foregroundStyle(Theme.accent)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).typography(.titleMedium).foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.labelMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
