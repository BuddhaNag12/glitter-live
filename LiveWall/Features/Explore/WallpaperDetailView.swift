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
    @State private var showsLockScreen = true
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
                    LockScreenPage(wallpaper: wallpaper, isCurrent: wallpaper.id == currentID, showsLockScreen: showsLockScreen)
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
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showsControls.toggle() } }
        .overlay(alignment: .top) {
            if showsControls { topBar.transition(.opacity) }
        }
        .overlay(alignment: .bottom) {
            if showsControls { panel.transition(.opacity.combined(with: .move(edge: .bottom))) }
        }
        // Each wallpaper starts with its own Save button.
        .onChange(of: currentID) { if !saver.isWorking { saver = WallpaperSaver() } }
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
            Button {
                withAnimation(.easeOut(duration: 0.25)) { showsLockScreen.toggle() }
            } label: {
                Image(systemName: showsLockScreen ? "lock.rectangle.on.rectangle" : "photo")
            }
            .buttonStyle(CircleIconButtonStyle(size: 40))
            .accessibilityLabel(showsLockScreen ? "Show the wallpaper only" : "Show the Lock Screen")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var panel: some View {
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(current.title).typography(.titleMedium).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(subtitle).font(.labelMedium).foregroundStyle(Theme.textSecondary).lineLimit(1)
                if current.isLive {
                    Text("Touch and hold the wallpaper to replay its motion")
                        .font(.labelSmall)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.2), value: current.id)

            if saver.phase == .saved {
                Button { showsGuide = true } label: {
                    Label("Saved to Photos · How to Set It", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(KineticButtonStyle())
            } else {
                Button {
                    Task { await saver.save(current, library: CreationLibrary(context: modelContext)) }
                } label: {
                    if saver.isWorking {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text(progressTitle)
                        }
                    } else if current.isLive {
                        Label("Save as Live Wallpaper", systemImage: "livephoto")
                    } else {
                        Label("Save as Wallpaper", systemImage: "photo")
                    }
                }
                .buttonStyle(KineticButtonStyle())
                .disabled(saver.isWorking)
            }
            if case .failed(let message) = saver.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.labelMedium)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .glass(.floating, cornerRadius: 28)
        .padding(.horizontal, 16)
        // Above the Lock Screen's flashlight and camera, which stay visible below it.
        .padding(.bottom, 72)
    }

    /// "Live · 4.0s · by Glitter Live · 2 of 6", or "Still · by …"; the clock's corners stay clear for the buttons.
    private var subtitle: String {
        var parts = [current.durationSeconds.map { "Live · \($0.formatted(.number.precision(.fractionLength(1))))s" } ?? "Still"]
        if let creator = current.creatorName { parts.append("by \(creator)") }
        if wallpapers.count > 1, let index = wallpapers.firstIndex(where: { $0.id == current.id }) {
            parts.append("\(index + 1) of \(wallpapers.count)")
        }
        return parts.joined(separator: " · ")
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
    let showsLockScreen: Bool

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
                if showsLockScreen { LockScreenOverlay().transition(.opacity) }
            }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.3) { if wallpaper.isLive { wakes += 1 } }
        .task(id: WakeKey(isCurrent: isCurrent, wakes: wakes)) {
            if isCurrent { await wake() } else { player?.pause() }
        }
        .accessibilityElement()
        .accessibilityLabel(wallpaper.title)
        .accessibilityHint(wallpaper.isLive ? "Touch and hold to play its motion again." : "")
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
