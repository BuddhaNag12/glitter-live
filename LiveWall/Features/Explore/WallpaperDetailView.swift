import AVFoundation
import SwiftData
import SwiftUI

/// Downloads a catalog wallpaper and turns it into a Lock Screen-ready Live Photo, or a framed still.
@Observable
final class WallpaperSaver {
    enum Phase: Equatable { case idle, downloading, creating, saving, saved, failed(String) }

    private(set) var phase: Phase = .idle

    var isWorking: Bool { [.downloading, .creating, .saving].contains(phase) }

    func save(_ wallpaper: Wallpaper, library: CreationLibrary) async {
        do {
            phase = .downloading
            let media = try await CatalogService.downloadMedia(wallpaper)
            guard wallpaper.isLive else { return try await saveStill(media, library: library) }
            let video = media
            phase = .creating
            let info = try await VideoInfo.load(video)
            let request = LivePhotoRequest.filling(source: video, uprightSize: info.uprightSize, duration: info.duration)
            var result = try await LivePhotoBuilder.build(request, in: .livePhotosDirectory)
            let creation = try? library.add(result, duration: min(info.duration, 5))
            if let creation { result = creation.livePhoto }
            phase = .saving
            try await LivePhotoSaver.save(result)
            creation?.savedToPhotos = true
            try? library.context.save()
            phase = .saved
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// The same chain as saving a generated still in Create.
    private func saveStill(_ image: URL, library: CreationLibrary) async throws {
        phase = .creating
        let still = try WallpaperStill.make(from: image)
        phase = .saving
        try await LivePhotoSaver.saveStill(still)
        // A library failure shouldn't undo a save that already reached Photos.
        try? library.addStill(still)
        phase = .saved
    }
}

/// A wallpaper as it really looks on the Lock Screen: full screen, edge to edge, with the clock, widgets and quick
/// actions at their true size. Swipe sideways through the wallpapers it was opened among, and down to close.
/// A tap hides the controls; the eye button hides the Lock Screen too, leaving the bare wallpaper.
struct WallpaperDetailView: View {
    let wallpapers: [Wallpaper]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var currentID: Wallpaper.ID?
    @State private var saver = WallpaperSaver()
    @State private var showsControls = true
    /// The title card shows for a moment, then fades away so the wallpaper is seen whole; a tap brings it back.
    @State private var showsDetails = true
    @State private var detailsShownAt = Date.now
    /// While a finger holds the wallpaper, the app's controls step aside so it's seen as it really is.
    @State private var isHolding = false
    @State private var showsGuide = false

    init(wallpapers: [Wallpaper], startingAt wallpaper: Wallpaper) {
        self.wallpapers = wallpapers.contains { $0.id == wallpaper.id } ? wallpapers : [wallpaper]
        _currentID = State(initialValue: wallpaper.id)
    }

    private var current: Wallpaper { wallpapers.first { $0.id == currentID } ?? wallpapers[0] }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(wallpapers) { wallpaper in
                    LockScreenPage(wallpaper: wallpaper, isCurrent: wallpaper.id == currentID) { holding in
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
        // A tap brings back whatever is hidden; with everything showing, it hides it all.
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
            if showsControls && !isHolding { topBar.transition(.opacity) }
        }
        .overlay(alignment: .bottom) {
            if showsControls && !isHolding { panel.transition(.opacity.combined(with: .move(edge: .bottom))) }
        }
        .overlay(alignment: .bottom) {
            // Level with the Lock Screen's flashlight and camera.
            if showsControls, !isHolding, wallpapers.count > 1 { position.padding(.bottom, 12).transition(.opacity) }
        }
        // Each wallpaper starts with its own Save button.
        .onChange(of: currentID) {
            if !saver.isWorking { saver = WallpaperSaver() }
            withAnimation(.easeOut(duration: 0.25)) { showDetails() }
        }
        .sheet(isPresented: $showsGuide) { SetWallpaperGuideView() }
        .sensoryFeedback(.selection, trigger: currentID)
        .sensoryFeedback(trigger: saver.phase) { _, phase in
            switch phase {
            case .saved: .success
            case .failed: .error
            default: nil
            }
        }
        // A Lock Screen is dark whatever the app's appearance.
        .environment(\.colorScheme, .dark)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(CircleIconButtonStyle(size: 40))
                .accessibilityLabel("Close")
            Spacer()
            saveButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    /// The details in a glass card, and beside it, on its own, the download button.
    /// The title and how to see the wallpaper whole, centred above the Lock Screen's flashlight and camera.
    private var panel: some View {
        VStack(spacing: 8) {
            // A long title wraps to a second line, then truncates.
            Text(current.title)
                .typography(.titleMedium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
            Label(current.isLive ? "Hold to see it live" : "Hold to see the full image", systemImage: "hand.tap.fill")
                .font(.labelMedium)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if case .failed(let message) = saver.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.labelMedium)
                    .foregroundStyle(Theme.danger)
            }
        }
        .multilineTextAlignment(.center)
        .contentTransition(.opacity)
        .animation(.easeOut(duration: 0.2), value: current.id)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .glass(.floating, cornerRadius: 24)
        .opacity(showsDetails || saver.phase != .idle ? 1 : 0)
        .blur(radius: showsDetails || saver.phase != .idle ? 0 : 8)
        .offset(y: showsDetails || saver.phase != .idle ? 0 : 10)
        .allowsHitTesting(showsDetails)
        .padding(.horizontal, 32)
        // Above the Lock Screen's flashlight and camera, which stay visible below it.
        .padding(.bottom, 72)
    }

    private func showDetails() {
        showsDetails = true
        detailsShownAt = .now
    }

    /// Which wallpaper this is, between the Lock Screen's flashlight and camera.
    private var position: some View {
        let index = (wallpapers.firstIndex { $0.id == current.id } ?? 0) + 1
        return Text("\(index) / \(wallpapers.count)")
            .font(.labelMedium.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .animation(.snappy, value: index)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(.black.opacity(0.35), in: Capsule())
            .accessibilityLabel("Wallpaper \(index) of \(wallpapers.count)")
    }

    /// One round button through the whole save: a download arrow, a spinning ring while it works, then a tick
    /// that opens the how-to-set guide. After a failure it shows "!" and tapping tries again.
    private var saveButton: some View {
        let symbol = switch saver.phase {
        case .saved: "checkmark"
        case .failed: "exclamationmark"
        default: "arrow.down.to.line"
        }
        return Button {
            // Not disabled while it works: a disabled button lets taps through to the page, which hides the panel.
            guard !saver.isWorking else { return }
            if saver.phase == .saved {
                showsGuide = true
            } else {
                Task { await saver.save(current, library: CreationLibrary(context: modelContext)) }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .overlay {
                    if saver.isWorking { SpinningRing().padding(3) }
                }
                .contentShape(Circle())
                .animation(.snappy, value: saver.phase)
        }
        .buttonStyle(PressScaleButtonStyle())
        // Clear Liquid Glass, like the tab bar. On the Button rather than its label, which is where glass inside
        // buttons has crashed iOS 27's renderer.
        .liquidGlass(in: Circle(), interactive: true)
        .accessibilityLabel(saveLabel)
        .accessibilityValue(progressTitle)
    }

    private var saveLabel: String {
        switch saver.phase {
        case .saved: "Saved to Photos. How to set it as your wallpaper"
        case .failed: "Couldn't save. Try again"
        default: current.isLive ? "Save as Live Wallpaper" : "Save as Wallpaper"
        }
    }

    private var progressTitle: String {
        switch saver.phase {
        case .downloading: "Downloading…"
        case .creating: current.isLive ? "Creating Live Photo…" : "Preparing…"
        case .saving: "Saving…"
        default: ""
        }
    }
}

/// One wallpaper filling the screen under the Lock Screen. A live one plays once when it comes into view, like
/// waking the iPhone, then settles on its cover photo (the clip's midpoint, as saved); touch and hold replays it.
private struct LockScreenPage: View {
    let wallpaper: Wallpaper
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
                    AsyncImage(url: wallpaper.isLive ? wallpaper.thumbnailURL : wallpaper.mediaURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if !wallpaper.isLive {
                            // The small thumbnail holds the place until the full image arrives.
                            AsyncImage(url: wallpaper.thumbnailURL) { $0.resizable().scaledToFill() } placeholder: { ProgressView().tint(.white) }
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
                if !(isHolding && !wallpaper.isLive) { LockScreenOverlay().transition(.opacity) }
            }
        .contentShape(Rectangle())
        // Hold: a live wallpaper plays its motion again, a still drops the Lock Screen; letting go puts it back.
        .onLongPressGesture(minimumDuration: 0.3) {
            if wallpaper.isLive { wakes += 1 }
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
        .accessibilityLabel(wallpaper.title)
        .accessibilityHint(wallpaper.isLive ? "Touch and hold to see it live." : "Touch and hold to see the full image.")
    }

    private struct WakeKey: Equatable { let isCurrent: Bool; let wakes: Int }

    private func wake() async {
        guard wallpaper.isLive, let file = try? await CatalogService.downloadMedia(wallpaper), !Task.isCancelled else { return }
        let player = self.player ?? AVPlayer(url: file)
        player.isMuted = true
        self.player = player
        let asset = AVURLAsset(url: file)
        let length = min((try? await asset.load(.duration))?.seconds ?? 0, 5)
        let coverTime = CMTime(seconds: length / 2, preferredTimescale: 600)
        if cover == nil {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            cover = (try? await generator.image(at: coverTime).image).map(UIImage.init(cgImage:))
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
