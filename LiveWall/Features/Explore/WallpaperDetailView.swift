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

/// Catalog wallpapers in the full-screen Lock Screen viewer, with a download button for each.
struct WallpaperDetailView: View {
    let wallpapers: [Wallpaper]
    let start: Wallpaper

    init(wallpapers: [Wallpaper], startingAt wallpaper: Wallpaper) {
        self.wallpapers = wallpapers.contains { $0.id == wallpaper.id } ? wallpapers : [wallpaper]
        start = wallpaper
    }

    var body: some View {
        LockScreenViewer(items: wallpapers.map(\.viewerItem), startingAt: start.id) { item in
            if let wallpaper = wallpapers.first(where: { $0.id == item.id }) {
                // One saver per wallpaper, so each page starts with its own button.
                // shortcut: swiping away mid-save drops the button's progress (the save itself finishes).
                CatalogSaveButton(wallpaper: wallpaper).id(wallpaper.id)
            }
        }
    }
}

private extension Wallpaper {
    var viewerItem: ViewerItem {
        ViewerItem(
            id: id,
            title: title,
            isLive: isLive,
            image: isLive ? thumbnailURL : mediaURL,
            placeholder: isLive ? nil : thumbnailURL,
            video: isLive ? { @Sendable [self] in try? await CatalogService.downloadMedia(self) } : nil
        )
    }
}

/// Downloads and saves a catalog wallpaper; once saved, it opens the how-to-set guide.
private struct CatalogSaveButton: View {
    let wallpaper: Wallpaper

    @Environment(\.modelContext) private var modelContext
    @State private var saver = WallpaperSaver()
    @State private var showsGuide = false

    var body: some View {
        SaveIconButton(phase: phase, label: label) {
            if saver.phase == .saved {
                showsGuide = true
            } else {
                Task { await saver.save(wallpaper, library: CreationLibrary(context: modelContext)) }
            }
        }
        .accessibilityValue(progress)
        .sheet(isPresented: $showsGuide) { SetWallpaperGuideView() }
        .alert("Couldn't save", isPresented: Binding(get: { failure != nil }, set: { if !$0 { saver = WallpaperSaver() } })) {
            Button("OK") {}
        } message: {
            Text(failure ?? "")
        }
    }

    private var failure: String? {
        if case .failed(let message) = saver.phase { message } else { nil }
    }

    private var phase: SaveIconButton.Phase {
        switch saver.phase {
        case .idle: .ready
        case .saved: .saved
        case .failed: .failed
        default: .working
        }
    }

    private var label: String {
        switch saver.phase {
        case .saved: "Saved to Photos. How to set it as your wallpaper"
        case .failed: "Couldn't save. Try again"
        default: wallpaper.isLive ? "Save as Live Wallpaper" : "Save as Wallpaper"
        }
    }

    private var progress: String {
        switch saver.phase {
        case .downloading: "Downloading…"
        case .creating: wallpaper.isLive ? "Creating Live Photo…" : "Preparing…"
        case .saving: "Saving…"
        default: ""
        }
    }
}
