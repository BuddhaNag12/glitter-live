import SwiftUI

struct TrimStudioView: View {
    @Bindable var editor: ConvertEditor
    var onClose: () -> Void

    /// Pan and pinch only reframe while this is on, so the page can scroll the rest of the time.
    @State private var isFraming = false
    @State private var confirmsDiscard = false
    @State private var choosesPayment = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(Purchases.self) private var purchases
    private let ads: any RewardedAdPresenter = PendingRewardedAds()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                toolbar
                CropPreview(editor: editor, isFraming: $isFraming)
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.74 }
                timelinePanel
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(isFraming)
        .task { await editor.load() }
        .overlay {
            if editor.phase == .exporting { exportingOverlay }
        }
        .animation(.spring(duration: 0.3), value: isFraming)
        .animation(.easeOut(duration: 0.2), value: editor.phase == .exporting)
        .confirmationDialog("Discard your edits?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: onClose)
        } message: {
            Text("Your trim, framing and cover photo will be lost.")
        }
        .confirmationDialog("You've used your \(ConversionAllowance.freeConversions) free conversions", isPresented: $choosesPayment, titleVisibility: .visible) {
            Button("Watch a Short Ad") {
                Task {
                    guard await ads.present() else { return }
                    editor.adWatched()
                    await editor.export()
                }
            }
            Button(purchases.unlockTitle) {
                Task {
                    guard await purchases.buyUnlimitedConversions() else { return }
                    await editor.export()
                }
            }
        } message: {
            Text("Watch a short ad to save this one, or unlock unlimited conversions with a one-time purchase.")
        }
        .alert("Something went wrong", isPresented: .constant(editor.errorMessage != nil)) {
            Button("OK") { editor.errorMessage = nil }
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack {
            // Only asks when there's work to lose.
            Button { editor.hasChanges ? (confirmsDiscard = true) : onClose() } label: { Image(systemName: "xmark") }
                .buttonStyle(CircleIconButtonStyle())
                .accessibilityLabel("Discard video")
            Spacer()
            StatusPill(text: "TRIM STUDIO")
            Spacer()
            Button(action: convert) {
                Label("Save", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(AccentCapsuleButtonStyle())
            .disabled(editor.phase != .editing)
        }
    }

    private var timelinePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle().fill(Theme.accent).frame(width: 10, height: 10)
                Text("Motion Timeline").typography(.headlineSmall).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Duration: \(Text(editor.outputDuration, format: .number.precision(.fractionLength(1))).foregroundStyle(Theme.accent))s")
                    .font(.labelMedium.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .liquidGlass(in: Capsule())
            }
            Text("Recommended: 1 – 3 s for smooth Lock Screen motion.")
                .font(.labelMedium)
                .foregroundStyle(Theme.textSecondary)

            TimelineStrip(editor: editor)

            keyFrameRow

            Text("MOTION ATTRIBUTES")
                .font(.labelSmall)
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            attributes

            Button(action: convert) {
                Label("Save Live Photo", systemImage: "livephoto")
            }
            .buttonStyle(KineticButtonStyle())
            .disabled(editor.phase != .editing)
            .padding(.top, 4)
        }
        .padding(20)
        .glass(.floating, cornerRadius: 30)
    }

    private var keyFrameRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo")
                .scaledIcon(size: 17, frame: 42)
                .foregroundStyle(Theme.slate)
                .background(Theme.slate.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Key Frame")
                        .typography(.titleMedium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(Self.timestamp(editor.coverOffset))
                        .font(.labelMedium.monospaced())
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }
                Text("Drag the blue marker to choose the cover photo.")
                    .font(.labelMedium)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glass(.surface, cornerRadius: 22)
    }

    /// Framing and the Lock Screen overlay are controlled on the preview they change, so this holds only the motion itself.
    /// Two columns, or one at accessibility text sizes so the labels don't truncate.
    @ViewBuilder
    private var attributes: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                speedCell
                bounceCell
            }
        } else {
            HStack(spacing: 12) {
                speedCell
                bounceCell
            }
        }
    }

    /// A menu shows every speed at once, where tapping to cycle hid them and had no way back.
    private var speedCell: some View {
        Menu {
            Picker("Speed", selection: $editor.speed) {
                ForEach(ConvertEditor.speeds, id: \.self) { speed in
                    Text(Self.speedLabel(speed)).tag(speed)
                }
            }
        } label: {
            AttributeCell(symbol: "gauge.with.dots.needle.67percent", title: "Speed") {
                ValueChip(text: Self.speedLabel(editor.speed), tint: Theme.slate)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var bounceCell: some View {
        toggleCell(symbol: "arrow.left.arrow.right", title: "Bounce", tint: Theme.accent, isOn: $editor.bounces)
    }

    /// A chip instead of a system switch, which doesn't fit beside a label in a half-width cell.
    private func toggleCell(symbol: String, title: String, tint: Color, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            AttributeCell(symbol: symbol, title: title, tint: tint, active: isOn.wrappedValue) {
                ValueChip(text: isOn.wrappedValue ? "On" : "Off", tint: isOn.wrappedValue ? Theme.accent : Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }

    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(Theme.accent)
                Text("Creating Live Photo…").typography(.titleMedium).foregroundStyle(Theme.textPrimary)
            }
            .padding(28)
            .glass(.floating, cornerRadius: 26)
        }
        .transition(.opacity)
    }

    private func convert() {
        isFraming = false
        guard !editor.needsPayment else {
            choosesPayment = true
            return
        }
        Task { await editor.export() }
    }

    static func speedLabel(_ speed: Double) -> String {
        "\(speed.formatted(.number.precision(.fractionLength(0...1))))×"
    }

    static func timestamp(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainder = seconds - Double(minutes * 60)
        return String(format: "%02d:%04.1f", minutes, remainder)
    }
}

private struct AttributeCell<Accessory: View>: View {
    let symbol: String
    let title: String
    var tint: Color = Theme.accent
    var active = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .scaledIcon(size: 16, weight: .medium, frame: 22)
                .foregroundStyle(tint)
            Text(title)
                .typography(.labelLarge)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 0)
            // The value is what the cell is for, so it keeps its full width and the title gives way.
            accessory.fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 60)
        .glass(.surface, cornerRadius: 20)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.accent.opacity(active ? 0.8 : 0), lineWidth: 1.5)
        }
        .contentShape(Rectangle())
    }
}

private struct ValueChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.labelMedium.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

/// Lock-screen preview. Pinching reframes at any time; dragging reframes in framing mode, so the page can scroll otherwise.
private struct CropPreview: View {
    @Bindable var editor: ConvertEditor
    @Binding var isFraming: Bool

    // Live gesture values stay until both gestures end, so the settle starts from what's on screen.
    @State private var dragTranslation: CGSize = .zero
    @State private var dragBase: CGSize?
    @State private var releaseVelocity: CGSize = .zero
    @State private var pinchScale: CGFloat = 1
    @State private var pinchBase: CGFloat?
    /// Where the pinch started, from the canvas center.
    @State private var pinchAnchor: CGSize = .zero
    @GestureState private var isDragging = false
    @GestureState private var isPinching = false
    /// The spring back after a gesture, run by hand so a new gesture can catch it where it is on screen.
    @State private var settling: FramingSettle?

    var body: some View {
        DeviceFrame(highlighted: isFraming) {
            TimelineView(.animation(paused: settling == nil)) { context in
                canvas(at: context.date)
            }
        }
        .task(id: settling) {
            guard settling != nil else { return }
            try? await Task.sleep(for: .seconds(FramingSettle.duration))
            if !Task.isCancelled { settling = nil }
        }
    }

    private func canvas(at date: Date) -> some View {
        let shown = framing(at: date)
        let videoSize = editor.displayedVideoSize(zoom: shown.zoom)

        return Color.black
            .overlay {
                PlayerLayerView(player: editor.player)
                    .frame(width: videoSize.width, height: videoSize.height)
                    .offset(shown.pan)
            }
            .overlay {
                if editor.showsLockScreen && !isFraming { LockScreenOverlay(showsMotionBadge: true) }
            }
            .overlay { if isFraming { framingGuide } }
            .overlay(alignment: .topTrailing) { previewControls }
            .clipped()
            .contentShape(Rectangle())
            .onGeometryChange(for: CGSize.self) { $0.size } action: { editor.canvasSize = $0 }
            .gesture(dragGesture, including: isFraming ? .all : .subviews)
            .simultaneousGesture(magnifyGesture)
            .onChange(of: isDragging || isPinching) { _, isActive in
                if !isActive { settle() }
            }
    }

    /// What's on screen: the settling spring, or the live gesture resisting past its limits.
    private func framing(at date: Date) -> (zoom: CGFloat, pan: CGSize) {
        if let settling { return settling.value(at: date) }
        let zoom = ConvertEditor.rubberBandedZoom(editor.zoom * pinchScale)
        return (zoom, editor.rubberBandedPan(proposedPan(zoom: zoom), zoom: zoom))
    }

    /// The pan that keeps the point under the pinch still at this zoom, plus the drag.
    private func proposedPan(zoom: CGFloat) -> CGSize {
        let ratio = zoom / ConvertEditor.rubberBandedZoom(editor.zoom)
        return CGSize(
            width: pinchAnchor.width - (pinchAnchor.width - editor.panOffset.width) * ratio + dragTranslation.width,
            height: pinchAnchor.height - (pinchAnchor.height - editor.panOffset.height) * ratio + dragTranslation.height
        )
    }

    private var framingGuide: some View {
        ZStack {
            GridLines().stroke(.white.opacity(0.35), lineWidth: 0.75)
            VStack {
                Spacer()
                Label("Drag and pinch to reframe", systemImage: "hand.draw")
                    .font(.labelMedium.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .liquidGlass(in: Capsule())
                    .padding(.bottom, 20)
            }
        }
        .allowsHitTesting(false)
    }

    private var previewControls: some View {
        GlassGroup(spacing: 8) {
            VStack(spacing: 8) {
                if isFraming {
                    Button { isFraming = false } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("Done framing")
                    Button {
                        springBack(zoom: 1, pan: .zero)
                    } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel("Reset framing")
                } else {
                    Button { isFraming = true } label: { Image(systemName: "viewfinder") }
                        .accessibilityLabel("Reframe video")
                    Button { editor.showsLockScreen.toggle() } label: {
                        Image(systemName: editor.showsLockScreen ? "eye" : "eye.slash")
                    }
                    .accessibilityLabel(editor.showsLockScreen ? "Hide Lock Screen overlay" : "Show Lock Screen overlay")
                    Button(action: editor.restartLoop) { Image(systemName: "hand.tap") }
                        .accessibilityLabel("Replay wake animation")
                }
            }
            .buttonStyle(CircleIconButtonStyle(size: 34))
        }
        .padding(10)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                if dragBase == nil { catchSettle() }
                // A pending translation stays in place if a new drag starts before the pinch ends.
                let base = dragBase ?? dragTranslation
                dragBase = base
                dragTranslation = CGSize(width: base.width + value.translation.width, height: base.height + value.translation.height)
                releaseVelocity = value.velocity
            }
            .onEnded { value in
                dragBase = nil
                releaseVelocity = value.velocity
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($isPinching) { _, state, _ in state = true }
            .onChanged { value in
                if !isFraming { isFraming = true }
                if pinchBase == nil {
                    catchSettle()
                    pinchBase = pinchScale
                    if pinchScale == 1 {
                        let canvas = editor.canvasSize
                        pinchAnchor = CGSize(
                            width: (value.startAnchor.x - 0.5) * canvas.width,
                            height: (value.startAnchor.y - 0.5) * canvas.height
                        )
                    }
                }
                pinchScale = (pinchBase ?? 1) * value.magnification
            }
            .onEnded { _ in
                pinchBase = nil
                // Only a drag that ends last throws the video.
                releaseVelocity = .zero
            }
    }

    /// Springs back inside the limits, carrying a flick on to where it was heading.
    private func settle() {
        let range = ConvertEditor.zoomRange
        let zoom = min(max(editor.zoom * pinchScale, range.lowerBound), range.upperBound)
        let proposed = proposedPan(zoom: zoom)
        let projected = CGSize(
            width: proposed.width + Motion.projection(of: releaseVelocity.width),
            height: proposed.height + Motion.projection(of: releaseVelocity.height)
        )
        springBack(zoom: zoom, pan: editor.clampedPan(projected, zoom: zoom), velocity: releaseVelocity)
        dragBase = nil
        pinchBase = nil
        releaseVelocity = .zero
    }

    /// Commits the target and springs to it from what's on screen, keeping the finger's speed on each axis.
    private func springBack(zoom: CGFloat, pan: CGSize, velocity: CGSize = .zero) {
        let now = Date.now
        let shown = framing(at: now)
        editor.zoom = zoom
        editor.panOffset = pan
        pinchScale = 1
        pinchAnchor = .zero
        dragTranslation = .zero
        settling = FramingSettle(
            start: now,
            zoom: CriticalSpring(from: shown.zoom, to: zoom),
            x: CriticalSpring(from: shown.pan.width, to: pan.width, velocity: velocity.width),
            y: CriticalSpring(from: shown.pan.height, to: pan.height, velocity: velocity.height)
        )
    }

    /// A new gesture picks the video up exactly where the spring has it, instead of jumping to its target.
    private func catchSettle() {
        guard let settling else { return }
        let shown = settling.value(at: .now)
        // Stored unresisted, so the live gesture draws it back at exactly the same place.
        let zoom = ConvertEditor.unrubberBandedZoom(shown.zoom)
        editor.zoom = zoom
        editor.panOffset = editor.unrubberBandedPan(shown.pan, zoom: ConvertEditor.rubberBandedZoom(zoom))
        self.settling = nil
    }
}

private struct FramingSettle: Equatable {
    static let duration: TimeInterval = 0.8

    var start: Date
    var zoom: CriticalSpring
    var x: CriticalSpring
    var y: CriticalSpring

    func value(at date: Date) -> (zoom: CGFloat, pan: CGSize) {
        let elapsed = min(max(date.timeIntervalSince(start), 0), Self.duration)
        return (zoom.value(after: elapsed), CGSize(width: x.value(after: elapsed), height: y.value(after: elapsed)))
    }
}

nonisolated private struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [1.0 / 3, 2.0 / 3] {
            path.move(to: CGPoint(x: rect.width * fraction, y: 0))
            path.addLine(to: CGPoint(x: rect.width * fraction, y: rect.height))
            path.move(to: CGPoint(x: 0, y: rect.height * fraction))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * fraction))
        }
        return path
    }
}
