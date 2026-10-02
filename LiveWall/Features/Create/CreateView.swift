import SwiftData
import SwiftUI

struct CreateView: View {
    @State private var model = CreateModel()
    @FocusState private var isPromptFocused: Bool
    @State private var showsStyles = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Stage { case compose, progress, image, live }

    private var stage: Stage {
        switch model.phase {
        case .composing: .compose
        case .makingImage, .addingMotion: .progress
        case .image: .image
        case .live: .live
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch stage {
            case .compose:
                composer.transition(.screen(reduceMotion: reduceMotion))
            case .progress:
                GenerationProgressView(phase: model.phase, style: model.style)
                    .transition(.screen(reduceMotion: reduceMotion))
            case .image:
                if case .image(let url) = model.phase {
                    GeneratedImageView(model: model, imageURL: url, library: CreationLibrary(context: modelContext))
                        .transition(.screen(reduceMotion: reduceMotion))
                }
            case .live:
                if let editor = model.editor {
                    ConvertFlowView(
                        editor: editor,
                        labels: .init(save: "Save Live Wallpaper", edit: "Edit Motion", new: "Back to Still", newSymbol: "photo"),
                        onClose: model.backToStill
                    )
                }
            }
        }
        .animation(.spring(duration: 0.4), value: stage)
        .screenHeader("Create")
        .sensoryFeedback(trigger: model.editor?.phase) { _, phase in
            if case .finished(_, saved: true) = phase { .success } else { nil }
        }
        .sensoryFeedback(.success, trigger: model.savedStill) { _, saved in saved }
        .sensoryFeedback(.error, trigger: model.errorMessage) { _, message in message != nil }
        .alert("Couldn't create", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var composer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AllowanceBanner(access: model.allowance.access)
                promptCard
                // Right after the prompt it acts on; the page fits on one screen with the styles folded away.
                generateButton
                    .padding(.top, 4)
            }
            .padding(16)
            .padding(.bottom, 24)
            // Taps between the cards land here and put the keyboard away; taps on controls still reach them.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isPromptFocused = false }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Describe a scene")
                    .typography(.titleMedium)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Surprise Me", systemImage: "dice", action: model.surprise)
                    .buttonStyle(GlassPillButtonStyle(tint: Theme.accent))
            }
            TextField("Bioluminescent koi in liquid starlight…", text: $model.prompt, axis: .vertical)
                .lineLimit(3...6)
                .typography(.bodyLarge)
                .foregroundStyle(Theme.textPrimary)
                .focused($isPromptFocused)
                // Prompts are one paragraph, so Return finishes typing instead of starting a new line.
                .submitLabel(.done)
                .onChange(of: model.prompt) { _, prompt in
                    guard prompt.contains("\n") else { return }
                    model.prompt = prompt.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                    isPromptFocused = false
                }
                .padding(16)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityLabel("Wallpaper description")
            HStack {
                styleButton
                Spacer()
                Text("\(model.prompt.count)/\(GenerationRequest.maximumPromptLength)")
                    .font(.labelMedium)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            if showsStyles {
                styleCards.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .glass(.floating, cornerRadius: 28)
        .sensoryFeedback(.selection, trigger: model.style)
    }

    /// Shows the chosen style; the cards stay folded away until it's tapped, so the prompt leads the page.
    private var styleButton: some View {
        Button {
            isPromptFocused = false
            withAnimation(.spring(duration: 0.35)) { showsStyles.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.style.symbol)
                Text(model.style.title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(showsStyles ? 180 : 0))
            }
        }
        .buttonStyle(GlassPillButtonStyle(tint: Theme.accent))
        .accessibilityLabel("Style, \(model.style.title)")
        .accessibilityHint(showsStyles ? "Hides the styles" : "Shows the styles")
    }

    private var styleCards: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(WallpaperStyle.allCases) { style in
                    StyleCard(style: style, isSelected: model.style == style) {
                        withAnimation(.spring(duration: 0.35)) {
                            model.style = style
                            showsStyles = false
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        // Bleeds to the card's edges, so cards scroll out past the padding instead of stopping at it.
        .contentMargins(.horizontal, 18, for: .scrollContent)
        .padding(.horizontal, -18)
    }

    private var generateButton: some View {
        Button {
            isPromptFocused = false
            Task { await model.generate() }
        } label: {
            Label(generateTitle, systemImage: generateSymbol)
        }
        .buttonStyle(KineticButtonStyle())
        .disabled(!model.canGenerate || RewardedAds.shared.isPreparing)
    }

    private var generateTitle: String {
        if RewardedAds.shared.isPreparing { return "Loading Ad…" }
        return switch model.allowance.access {
        case .unlimited, .free, .pro: "Generate Wallpaper"
        case .ad: "Watch Ad & Generate"
        case .dailyLimitReached: "Back Tomorrow"
        case .monthlyLimitReached: "Back Next Month"
        }
    }

    private var generateSymbol: String {
        if case .ad = model.allowance.access { "play.rectangle" } else { "wand.and.stars" }
    }
}

/// How the next generation is paid for, so an ad never comes as a surprise.
private struct AllowanceBanner: View {
    let access: GenerationAllowance.Access

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .scaledIcon(size: 17, weight: .semibold, frame: 40)
                .foregroundStyle(Theme.accent)
                .liquidGlass(in: Circle(), tint: Theme.accent.opacity(0.18))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).typography(.titleMedium).foregroundStyle(Theme.textPrimary)
                Text(detail).typography(.bodyMedium).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glass(.floating, cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch access {
        case .unlimited: "hammer"
        case .free: "gift"
        case .ad: "play.rectangle"
        case .pro: "crown"
        case .dailyLimitReached, .monthlyLimitReached: "hourglass"
        }
    }

    private var title: String {
        switch access {
        case .unlimited: "Testing mode"
        case .free(let remaining): remaining == 1 ? "1 free generation left" : "\(remaining) free generations left"
        case .ad: "Free with a short ad"
        case .pro: "Glitter Live Pro"
        case .dailyLimitReached: "That's today's generations"
        case .monthlyLimitReached: "That's this month's generations"
        }
    }

    private var detail: String {
        switch access {
        case .unlimited: "No limits or ads in this build."
        case .free: "After that, a short ad unlocks each one."
        case .ad(let remaining): "\(remaining) left today. Pro removes ads."
        case .pro(let remaining): "No ads. \(remaining) left this month."
        case .dailyLimitReached: "\(GenerationAllowance.dailyAdGenerations) more tomorrow, or go Pro for \(GenerationAllowance.monthlyProGenerations) a month without ads."
        case .monthlyLimitReached: "Your \(GenerationAllowance.monthlyProGenerations) generations refill next month."
        }
    }
}

private struct StyleCard: View {
    let style: WallpaperStyle
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                AuroraView(colors: style.palette.map { Color(hex: $0) }, isAnimated: false)
                    .frame(width: 76, height: 96)
                    .overlay {
                        Image(systemName: style.symbol)
                            .scaledIcon(size: 22, weight: .medium)
                            .foregroundStyle(.white)
                    }
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2.5 : 1))
                Text(style.title)
                    .font(.labelMedium.weight(.semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The wallpaper taking shape on a Lock Screen, with what's happening in plain words.
private struct GenerationProgressView: View {
    let phase: CreateModel.Phase
    let style: WallpaperStyle
    @State private var image: UIImage?

    private var imageURL: URL? {
        if case .addingMotion(let url) = phase { url } else { nil }
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            DeviceFrame {
                AuroraView(colors: style.palette.map { Color(hex: $0) })
                    // An overlay takes the frame's size, so a square image is cropped rather than widening the phone.
                    .overlay {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                        }
                    }
                    .clipped()
                    .shimmer()
                .overlay { LockScreenOverlay() }
            }
            .frame(width: 190)
            .animation(.easeOut(duration: 0.5), value: image != nil)

            VStack(spacing: 6) {
                Text(imageURL == nil ? "Painting your wallpaper" : "Adding motion")
                    .typography(.headlineSmall)
                    .foregroundStyle(Theme.textPrimary)
                Text(imageURL == nil ? "This usually takes about 10 seconds." : "Turning it into a 3-second loop.")
                    .typography(.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
            }
            .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .task(id: imageURL) {
            guard let imageURL else { return image = nil }
            image = UIImage(contentsOfFile: imageURL.path(percentEncoded: false))
        }
    }
}
