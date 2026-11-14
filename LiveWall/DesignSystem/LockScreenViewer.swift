import AVFoundation
import SwiftUI

/// A wallpaper the Lock Screen viewer can show: from the catalog, the Library or Create.
struct ViewerItem: Identifiable {
    let id: UUID
    let title: String
    let isLive: Bool
    /// A still's picture, or a live wallpaper's poster until its movie arrives.
    let image: URL
    /// A smaller picture shown while `image` loads.
    var placeholder: URL?
    /// The movie, fetched when its page comes into view.
    var video: (@Sendable () async -> URL?)?
}

/// Wallpapers as they really look on the Lock Screen: full screen, edge to edge, with the clock, widgets and quick
/// actions at their true size. Swipe sideways between them and down to close (with the zoom transition).
/// The title card fades after 2 seconds; a tap brings it back, and a tap with everything showing hides the controls.
/// Holding plays a live wallpaper's motion, or shows a still without the Lock Screen over it.
/// `actions` fills the top-right corner for the current wallpaper.
struct LockScreenViewer<Actions: View>: View {
    let items: [ViewerItem]
    @ViewBuilder var actions: (ViewerItem) -> Actions

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: UUID?
    @State private var showsControls = true
    @State private var showsDetails = true
    @State private var detailsShownAt = Date.now
    @State private var isHolding = false

    init(items: [ViewerItem], startingAt id: UUID, @ViewBuilder actions: @escaping (ViewerItem) -> Actions) {
        self.items = items
        self.actions = actions
        _currentID = State(initialValue: id)
    }

    private var current: ViewerItem? { items.first { $0.id == currentID } ?? items.first }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(items) { item in
                    LockScreenPage(item: item, isCurrent: item.id == current?.id) { holding in
                        withAnimation(.easeOut(duration: 0.2)) { isHolding = holding }
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .background(.black)
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.25)) {
                if showsControls && showsDetails {
                    showsControls = false
                } else {
                    showsControls = true
                    showDetails()
                }
            }
        }
        .task(id: detailsShownAt) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) { showsDetails = false }
        }
        .overlay(alignment: .top) {
            if showsControls && !isHolding, let current { topBar(current).transition(.opacity) }
        }
        .overlay(alignment: .bottom) {
            if showsControls && !isHolding, let current { card(current).transition(.opacity) }
        }
        .overlay(alignment: .bottom) {
            // Level with the Lock Screen's flashlight and camera.
            if showsControls, !isHolding, items.count > 1 { position.padding(.bottom, 12).transition(.opacity) }
        }
        .onChange(of: currentID) { withAnimation(.easeOut(duration: 0.25)) { showDetails() } }
        // The last one was deleted from under it.
        .onChange(of: items.isEmpty) { _, isEmpty in if isEmpty { dismiss() } }
        .sensoryFeedback(.selection, trigger: currentID)
        // A Lock Screen is dark whatever the app's appearance.
        .environment(\.colorScheme, .dark)
    }

    private func topBar(_ item: ViewerItem) -> some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(CircleIconButtonStyle(size: 40))
                .accessibilityLabel("Close")
            Spacer()
            actions(item)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    /// The title and how to see the wallpaper whole, centred above the flashlight and camera.
    private func card(_ item: ViewerItem) -> some View {
        VStack(spacing: 8) {
            // A long title wraps to a second line, then truncates.
            Text(item.title)
                .typography(.titleMedium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
            Label(item.isLive ? "Hold to see it live" : "Hold to see the full image", systemImage: "hand.tap.fill")
                .font(.labelMedium)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .multilineTextAlignment(.center)
        .contentTransition(.opacity)
        .animation(.easeOut(duration: 0.2), value: item.id)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .glass(.floating, cornerRadius: 24)
        .opacity(showsDetails ? 1 : 0)
        .blur(radius: showsDetails ? 0 : 8)
        .offset(y: showsDetails ? 0 : 10)
        .allowsHitTesting(showsDetails)
        .padding(.horizontal, 32)
        .padding(.bottom, 72)
    }

    private func showDetails() {
        showsDetails = true
        detailsShownAt = .now
    }

    /// Which wallpaper this is, between the Lock Screen's flashlight and camera.
    private var position: some View {
        let index = (items.firstIndex { $0.id == current?.id } ?? 0) + 1
        return Text("\(index) / \(items.count)")
            .font(.labelMedium.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .animation(.snappy, value: index)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(.black.opacity(0.35), in: Capsule())
            .accessibilityLabel("Wallpaper \(index) of \(items.count)")
    }
}

/// One wallpaper filling the screen under the Lock Screen. A live one plays once when it comes into view, like
/// waking the iPhone, then settles on its cover photo (the clip's midpoint, as saved); touch and hold replays it.
private struct LockScreenPage: View {
    let item: ViewerItem
    let isCurrent: Bool
    var onHold: (Bool) -> Void = { _ in }

    @State private var isHolding = false
    @State private var player: AVPlayer?
    @State private var cover: UIImage?
    @State private var showsCover = false
    @State private var wakes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The screen-sized colour sets the page's size; the wallpaper fills it and is clipped, so a picture of a
        // different shape can't stretch the page and, with it, the Lock Screen's clock and widgets.
        Theme.lockScreen
            .overlay {
                ZStack {
                    AsyncImage(url: item.image) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if let placeholder = item.placeholder {
                            AsyncImage(url: placeholder) { $0.resizable().scaledToFill() } placeholder: { ProgressView().tint(.white) }
                        }
                    }
                    if let player { PlayerLayerView(player: player) }
                    if let cover, showsCover {
                        Image(uiImage: cover).resizable().scaledToFill().transition(.opacity)
                    }
                }
            }
            .clipped()
            .overlay {
                // Holding a still shows the full image, without the clock and widgets over it.
                if !(isHolding && !item.isLive) { LockScreenOverlay().transition(.opacity) }
            }
            .contentShape(Rectangle())
            // Hold: a live wallpaper plays its motion again, a still drops the Lock Screen; letting go puts it back.
            .onLongPressGesture(minimumDuration: 0.3) {
                if item.isLive { wakes += 1 }
                withAnimation(.easeOut(duration: 0.2)) { isHolding = true }
                onHold(true)
            } onPressingChanged: { pressing in
                guard !pressing, isHolding else { return }
                withAnimation(.easeOut(duration: 0.2)) { isHolding = false }
                onHold(false)
            }
            .task(id: WakeKey(isCurrent: isCurrent, wakes: wakes)) {
                if isCurrent { await wake() } else { player?.pause() }
            }
            .accessibilityElement()
            .accessibilityLabel(item.title)
            .accessibilityHint(item.isLive ? "Touch and hold to see it live." : "Touch and hold to see the full image.")
    }

    private struct WakeKey: Equatable { let isCurrent: Bool; let wakes: Int }

    private func wake() async {
        guard item.isLive, let file = await item.video?(), !Task.isCancelled else { return }
        let player = self.player ?? AVPlayer(url: file)
        player.isMuted = true
        self.player = player
        let asset = AVURLAsset(url: file)
        let length = min((try? await asset.load(.duration))?.seconds ?? 0, 5)
        if cover == nil {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            cover = (try? await generator.image(at: CMTime(seconds: length / 2, preferredTimescale: 600)).image).map(UIImage.init(cgImage:))
        }
        guard !Task.isCancelled else { return }
        // Reduce Motion: no wake, just the cover photo, as the Lock Screen does.
        guard !reduceMotion, length > 0 else { return withAnimation { showsCover = true } }
        showsCover = false
        await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        try? await Task.sleep(for: .seconds(length))
        guard !Task.isCancelled else { return player.pause() }
        player.pause()
        withAnimation(.easeInOut(duration: 0.35)) { showsCover = true }
    }
}

/// A round, clear Liquid Glass button that carries a whole save: a download arrow, a spinning ring while it works,
/// a tick once saved, and "!" after a failure.
struct SaveIconButton: View {
    enum Phase: Equatable { case ready, working, saved, failed }

    let phase: Phase
    let label: String
    let action: () -> Void

    var body: some View {
        let symbol = switch phase {
        case .saved: "checkmark"
        case .failed: "exclamationmark"
        default: "arrow.down.to.line"
        }
        Button {
            // Not disabled while it works: a disabled button lets taps through to the page, which hides the controls.
            if phase != .working { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .overlay {
                    if phase == .working { SpinningRing().padding(3) }
                }
                .contentShape(Circle())
                .animation(.snappy, value: phase)
        }
        .buttonStyle(PressScaleButtonStyle())
        // On the Button rather than its label, which is where glass inside buttons has crashed iOS 27's renderer.
        .liquidGlass(in: Circle(), interactive: true)
        .accessibilityLabel(label)
        .sensoryFeedback(trigger: phase) { _, phase in
            switch phase {
            case .saved: .success
            case .failed: .error
            default: nil
            }
        }
    }
}

/// A quarter arc turning once a second around the save button while it works.
private struct SpinningRing: View {
    var body: some View {
        TimelineView(.animation) { context in
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
        }
        .accessibilityHidden(true)
    }
}
