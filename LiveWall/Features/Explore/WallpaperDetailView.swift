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

struct WallpaperDetailView: View {
    let wallpaper: Wallpaper

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var saver = WallpaperSaver()
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
    @State private var showsGuide = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DeviceFrame {
                        Theme.lockScreen
                            .overlay {
                                if wallpaper.isLive {
                                    PlayerLayerView(player: player)
                                } else {
                                    AsyncImage(url: wallpaper.mediaURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                }
                            }
                            .overlay { LockScreenOverlay(showsMotionBadge: wallpaper.isLive) }
                    }
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.56 }

                    VStack(spacing: 4) {
                        Text(wallpaper.title).typography(.headlineSmall).foregroundStyle(Theme.textPrimary)
                        if let creator = wallpaper.creatorName {
                            Group {
                                if let url = wallpaper.creatorURL {
                                    Link("by \(creator)", destination: url)
                                } else {
                                    Text("by \(creator)")
                                }
                            }
                            .font(.labelMedium)
                            .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    actions
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background { AppBackground(twinkles: false) }
            .navigationTitle(wallpaper.category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: startPreview)
        .onDisappear { player.pause() }
        .sheet(isPresented: $showsGuide) {
            SetWallpaperGuideView()
        }
        .sensoryFeedback(trigger: saver.phase) { _, phase in
            switch phase {
            case .saved: .success
            case .failed: .error
            default: nil
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if saver.phase == .saved {
                StatusPill(text: "SAVED TO PHOTOS", highlighted: true, symbol: "checkmark")
                Button { showsGuide = true } label: {
                    Label("Set as Wallpaper", systemImage: "iphone.gen3")
                }
                .buttonStyle(KineticButtonStyle())
            } else {
                Button {
                    Task { await saver.save(wallpaper, library: CreationLibrary(context: modelContext)) }
                } label: {
                    if saver.isWorking {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text(progressTitle)
                        }
                    } else {
                        if wallpaper.isLive {
                            Label("Save as Live Wallpaper", systemImage: "livephoto")
                        } else {
                            Label("Save as Wallpaper", systemImage: "photo")
                        }
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
            Text("Saved to Photos and your Library, ready for the Lock Screen.")
                .font(.labelMedium)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .glass(.floating, cornerRadius: 30)
    }

    private var progressTitle: String {
        switch saver.phase {
        case .downloading: "Downloading…"
        case .creating: wallpaper.isLive ? "Creating Live Photo…" : "Preparing…"
        case .saving: "Saving…"
        default: ""
        }
    }

    private func startPreview() {
        guard let videoURL = wallpaper.videoURL else { return }
        guard looper == nil else { return player.play() }
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: videoURL))
        player.play()
    }
}
