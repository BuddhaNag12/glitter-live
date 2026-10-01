import SwiftData
import SwiftUI

struct CreateView: View {
    @State private var model = CreateModel()
    @AppStorage("create.convertsOnTheGo") private var convertsOnTheGo = true
    @FocusState private var isPromptFocused: Bool
    @State private var showsStyles = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Stage { case compose, progress, edit }

    private var stage: Stage {
        switch model.phase {
        case .composing: .compose
        case .editing: .edit
        default: .progress
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
            case .edit:
                if let editor = model.editor {
                    ConvertFlowView(editor: editor, newTitle: "New Wallpaper", onClose: model.startOver)
                }
            }
        }
        .animation(.spring(duration: 0.4), value: stage)
        .screenHeader("Create")
        .sensoryFeedback(trigger: model.editor?.phase) { _, phase in
            if case .finished(_, saved: true) = phase { .success } else { nil }
        }
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
                onTheGoToggle
            }
            .padding(16)
            // Taps between the cards land here and put the keyboard away; taps on controls still reach them.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isPromptFocused = false }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // Pinned, so the main action is always in reach, above the tab bar or the keyboard.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            generateButton
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
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

    private var onTheGoToggle: some View {
        Toggle(isOn: $convertsOnTheGo) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Convert on the go")
                    .typography(.labelLarge)
                    .foregroundStyle(Theme.textPrimary)
                Text(convertsOnTheGo ? "Saves straight to Library and Photos" : "Opens in Trim Studio first")
                    .font(.labelMedium)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .toggleStyle(CompactSwitchStyle())
        .tint(Theme.accentFill)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glass(.floating, cornerRadius: 20)
    }

    private var generateButton: some View {
        Button {
            isPromptFocused = false
            Task { await model.generate(convertsOnTheGo: convertsOnTheGo, library: CreationLibrary(context: modelContext)) }
        } label: {
            Label(generateTitle, systemImage: generateSymbol)
        }
        .buttonStyle(KineticButtonStyle())
        .disabled(!model.canGenerate)
    }

    private var generateTitle: String {
        switch model.allowance.access {
        case .free, .pro: "Generate Live Wallpaper"
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
        case .free: "gift"
        case .ad: "play.rectangle"
        case .pro: "crown"
        case .dailyLimitReached, .monthlyLimitReached: "hourglass"
        }
    }

    private var title: String {
        switch access {
        case .free(let remaining): remaining == 1 ? "1 free generation left" : "\(remaining) free generations left"
        case .ad: "Free with a short ad"
        case .pro: "Glitter Live Pro"
        case .dailyLimitReached: "That's today's generations"
        case .monthlyLimitReached: "That's this month's generations"
        }
    }

    private var detail: String {
        switch access {
        case .free: "After that, a short ad unlocks each one."
        case .ad(let remaining): "\(remaining) left today. Pro removes ads."
        case .pro(let remaining): "No ads. \(remaining) left this month."
        case .dailyLimitReached: "\(GenerationAllowance.dailyAdGenerations) more tomorrow, or go Pro for \(GenerationAllowance.monthlyProGenerations) a month without ads."
        case .monthlyLimitReached: "Your \(GenerationAllowance.monthlyProGenerations) generations refill next month."
        }
    }
}

/// A switch at 80% size, for a secondary setting that shouldn't outweigh the content around it.
private struct CompactSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 0)
            Toggle(configuration)
                .labelsHidden()
                .scaleEffect(0.8, anchor: .trailing)
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

    private var step: Int {
        switch phase {
        case .animating: 1
        case .converting: 2
        default: 0
        }
    }

    private var imageURL: URL? {
        switch phase {
        case .animating(let url), .converting(let url): url
        default: nil
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            DeviceFrame {
                ZStack {
                    AuroraView(colors: style.palette.map { Color(hex: $0) })
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                    }
                }
                .shimmer(step < 2)
                .overlay { LockScreenOverlay() }
            }
            .frame(width: 190)
            .animation(.easeOut(duration: 0.5), value: image != nil)

            VStack(spacing: 6) {
                Text(title).typography(.headlineSmall).foregroundStyle(Theme.textPrimary)
                Text(detail).typography(.bodyMedium).foregroundStyle(Theme.textSecondary)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.accentFill : Theme.placeholder)
                        .frame(width: 28, height: 4)
                }
            }
            .animation(.spring(duration: 0.4), value: step)
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .task(id: imageURL) {
            guard let imageURL else { return image = nil }
            image = UIImage(contentsOfFile: imageURL.path())
        }
    }

    private var title: String {
        switch step {
        case 0: "Painting your wallpaper"
        case 1: "Bringing it to life"
        default: "Making it a Live Photo"
        }
    }

    private var detail: String {
        switch step {
        case 0: "This usually takes a few seconds."
        case 1: "Turning it into a 3-second loop."
        default: "Saving to your Library and Photos."
        }
    }
}
