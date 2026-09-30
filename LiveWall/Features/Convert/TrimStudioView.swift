import SwiftUI

struct TrimStudioView: View {
    @Bindable var editor: ConvertEditor
    var onClose: () -> Void

    @State private var isPickingCover = false
    /// Pan and pinch only reframe while this is on, so the page can scroll the rest of the time.
    @State private var isFraming = false

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
        .animation(.spring(duration: 0.3), value: isPickingCover)
        .alert("Something went wrong", isPresented: .constant(editor.errorMessage != nil)) {
            Button("OK") { editor.errorMessage = nil }
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack {
            Button(action: onClose) { Image(systemName: "xmark") }
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
                Circle().fill(Theme.cyan).frame(width: 10, height: 10).shadow(color: Theme.cyan, radius: 5)
                Text("Motion Timeline").font(.headlineSmall).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Duration: \(Text(editor.outputDuration, format: .number.precision(.fractionLength(1))).foregroundStyle(Theme.cyan))s")
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
                Label("Convert to Live Photo & Save", systemImage: "livephoto")
            }
            .buttonStyle(KineticButtonStyle())
            .disabled(editor.phase != .editing)
            .padding(.top, 4)

            Label("Free, no watermark. Saves a HEIC cover photo paired with an HEVC video.", systemImage: "checkmark.seal")
                .font(.labelMedium)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .glass(.floating, cornerRadius: 30)
    }

    private var keyFrameRow: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.lavender)
                    .frame(width: 42, height: 42)
                    .background(Theme.lavender.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key Frame")
                        .font(.titleMedium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(Self.timestamp(editor.coverOffset))
                            .font(.labelMedium.monospaced())
                            .foregroundStyle(Theme.cyan)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(Theme.cyan.opacity(0.12), in: Capsule())
                        Text("Cover photo")
                            .font(.labelMedium)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button(isPickingCover ? "Done" : "Change") {
                    isPickingCover.toggle()
                    isPickingCover ? editor.showCoverFrame() : editor.resumePreview()
                }
                .buttonStyle(GlassPillButtonStyle(tint: isPickingCover ? Theme.cyan : nil))
            }
            if isPickingCover {
                Slider(value: $editor.coverOffset, in: editor.coverRange)
                    .tint(Theme.cyan)
                    .onChange(of: editor.coverOffset) { editor.showCoverFrame() }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .glass(.surface, cornerRadius: 22)
    }

    private var attributes: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Button { isFraming.toggle() } label: {
                    AttributeCell(symbol: "viewfinder", title: "Framing", active: isFraming) {
                        ValueChip(text: isFraming ? "Adjusting" : "Fill", tint: Theme.cyan)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Turns on pan and pinch in the preview")

                Button(action: cycleSpeed) {
                    AttributeCell(symbol: "gauge.with.dots.needle.67percent", title: "Speed") {
                        ValueChip(text: "\(editor.speed.formatted(.number.precision(.fractionLength(0...1))))x", tint: Theme.lavender)
                    }
                }
                .buttonStyle(.plain)
            }
            GridRow {
                toggleCell(symbol: "arrow.left.arrow.right", title: "Bounce", tint: Theme.magenta, isOn: $editor.bounces)
                toggleCell(symbol: "lock.rectangle", title: "HUD", tint: Theme.cyan, isOn: $editor.showsLockScreen)
            }
        }
    }

    /// A chip instead of a system switch, which doesn't fit beside a label in a half-width cell.
    private func toggleCell(symbol: String, title: String, tint: Color, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            AttributeCell(symbol: symbol, title: title, tint: tint, active: isOn.wrappedValue) {
                ValueChip(text: isOn.wrappedValue ? "On" : "Off", tint: isOn.wrappedValue ? Theme.cyan : Theme.textTertiary)
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
                ProgressView().controlSize(.large).tint(Theme.cyan)
                Text("Creating Live Photo…").font(.titleMedium).foregroundStyle(Theme.textPrimary)
            }
            .padding(28)
            .glass(.floating, cornerRadius: 26)
        }
        .transition(.opacity)
    }

    private func convert() {
        isFraming = false
        isPickingCover = false
        Task { await editor.export() }
    }

    private func cycleSpeed() {
        let speeds = ConvertEditor.speeds
        let index = speeds.firstIndex(of: editor.speed) ?? 0
        editor.speed = speeds[(index + 1) % speeds.count]
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
    var tint: Color = Theme.cyan
    var active = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(title)
                .font(.titleMedium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            accessory
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 60)
        .glass(.surface, cornerRadius: 20)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.cyan.opacity(active ? 0.8 : 0), lineWidth: 1.5)
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

/// Lock-screen preview. In framing mode, drag and pinch reposition the video.
private struct CropPreview: View {
    @Bindable var editor: ConvertEditor
    @Binding var isFraming: Bool
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        DeviceFrame(highlighted: isFraming) {
            canvas
        }
    }

    private var canvas: some View {
        let zoom = min(max(editor.zoom * magnification, 1), 4)
        let pan = editor.clampedPan(
            CGSize(width: editor.panOffset.width + dragTranslation.width, height: editor.panOffset.height + dragTranslation.height),
            zoom: zoom
        )
        let videoSize = editor.displayedVideoSize(zoom: zoom)

        return Color.black
            .overlay {
                PlayerLayerView(player: editor.player)
                    .frame(width: videoSize.width, height: videoSize.height)
                    .offset(pan)
            }
            .overlay {
                if editor.showsLockScreen && !isFraming { LockScreenOverlay(showsMotionBadge: true) }
            }
            .overlay { if isFraming { framingGuide } }
            .overlay(alignment: .topTrailing) { previewControls }
            .clipped()
            .contentShape(Rectangle())
            .onGeometryChange(for: CGSize.self) { $0.size } action: { editor.canvasSize = $0 }
            .gesture(dragGesture.simultaneously(with: magnifyGesture), including: isFraming ? .all : .subviews)
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
                    Button(action: editor.resetFraming) { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel("Reset framing")
                } else {
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
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                let proposed = CGSize(
                    width: editor.panOffset.width + value.translation.width,
                    height: editor.panOffset.height + value.translation.height
                )
                editor.panOffset = editor.clampedPan(proposed, zoom: editor.zoom)
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in state = value.magnification }
            .onEnded { value in
                editor.zoom = min(max(editor.zoom * value.magnification, 1), 4)
                editor.panOffset = editor.clampedPan(editor.panOffset, zoom: editor.zoom)
            }
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
