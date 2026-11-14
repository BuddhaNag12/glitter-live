import SwiftData
import SwiftUI

/// Library wallpapers in the full-screen Lock Screen viewer: save to Photos from the corner, and more in its menu.
struct CreationDetailView: View {
    let creations: [Creation]
    let start: Creation

    var body: some View {
        LockScreenViewer(items: creations.map(\.viewerItem), startingAt: start.id) { item in
            if let creation = creations.first(where: { $0.id == item.id }) {
                CreationActions(creation: creation).id(creation.id)
            }
        }
    }
}

private extension Creation {
    var viewerItem: ViewerItem {
        let video = livePhoto.videoURL
        return ViewerItem(
            id: id,
            title: createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()),
            isLive: isLive,
            image: imageURL,
            video: isLive ? { @Sendable in video } : nil
        )
    }
}

/// Save (or, once saved, how to set it), and a menu with Add Motion, Save Again and Delete.
private struct CreationActions: View {
    let creation: Creation

    @Environment(\.modelContext) private var modelContext
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmsDelete = false
    @State private var showsGuide = false
    @State private var addsMotion = false

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                if !creation.isLive {
                    Button("Add Motion", systemImage: "sparkles") { addsMotion = true }
                }
                if creation.savedToPhotos {
                    Button("Save Again", systemImage: "square.and.arrow.down", action: save)
                }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(CircleIconButtonStyle(size: 40))
            .accessibilityLabel("More")

            SaveIconButton(phase: phase, label: creation.savedToPhotos ? "Saved to Photos. How to set it as your wallpaper" : "Save to Photos") {
                if creation.savedToPhotos { showsGuide = true } else { save() }
            }
        }
        .sheet(isPresented: $showsGuide) { SetWallpaperGuideView(isLive: creation.isLive) }
        .fullScreenCover(isPresented: $addsMotion) { AddMotionView(imageURL: creation.imageURL) }
        .confirmationDialog("Delete this wallpaper from Glitter Live?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("Any copy you saved to Photos stays there.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var phase: SaveIconButton.Phase {
        if isSaving { return .working }
        if errorMessage != nil { return .failed }
        return creation.savedToPhotos ? .saved : .ready
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                if creation.isLive {
                    try await LivePhotoSaver.save(creation.livePhoto)
                } else {
                    try await LivePhotoSaver.saveStill(creation.imageURL)
                }
                creation.savedToPhotos = true
                try? modelContext.save()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The viewer closes itself once nothing is left to show.
    private func delete() {
        do {
            try CreationLibrary(context: modelContext).delete(creation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
