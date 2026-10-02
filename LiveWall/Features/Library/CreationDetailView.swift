import PhotosUI
import SwiftData
import SwiftUI

struct CreationDetailView: View {
    let creation: Creation

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var livePhoto: PHLivePhoto?
    @State private var still: UIImage?
    @State private var filesMissing = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmsDelete = false
    @State private var showsGuide = false
    @State private var addsMotion = false
    /// Counts successful saves, so "Save Again" confirms with a haptic too.
    @State private var saves = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DeviceFrame {
                        Group {
                            if creation.isLive {
                                LivePhotoView(livePhoto: livePhoto)
                            } else {
                                Theme.lockScreen.overlay {
                                    if let still { Image(uiImage: still).resizable().scaledToFill() }
                                }
                                .clipped()
                            }
                        }
                        .overlay { LockScreenOverlay() }
                        .overlay(alignment: .topLeading) {
                            StatusPill(text: creation.isLive ? "LIVE" : "STILL", dot: creation.isLive ? Theme.signalYellow : Theme.slate)
                                .padding(12)
                        }
                    }
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.5 }

                    if filesMissing {
                        Label("This wallpaper's files are missing.", systemImage: "exclamationmark.triangle")
                            .font(.labelMedium)
                            .foregroundStyle(Theme.signalYellow)
                    } else if creation.isLive {
                        Label("Touch and hold the preview to play it", systemImage: "hand.tap")
                            .font(.labelMedium)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    actions
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background { AppBackground(twinkles: false) }
            .navigationTitle(Text(creation.createdAt, format: .dateTime.month(.wide).day().hour().minute()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: creation.id) {
            guard creation.isLive else {
                still = UIImage(contentsOfFile: creation.imageURL.path(percentEncoded: false))
                filesMissing = still == nil
                return
            }
            do {
                livePhoto = try await LivePhotoLoader.load(creation.livePhoto)
            } catch {
                filesMissing = true
            }
        }
        .sheet(isPresented: $showsGuide) {
            SetWallpaperGuideView().presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $addsMotion) {
            AddMotionView(imageURL: creation.imageURL)
        }
        .sensoryFeedback(.success, trigger: saves)
        .sensoryFeedback(.error, trigger: errorMessage) { _, message in message != nil }
        .confirmationDialog("Delete this wallpaper from Glitter Live?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("Any copy you saved to Photos stays there.")
        }
        .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var actions: some View {
        VStack(spacing: 14) {
            if creation.savedToPhotos {
                Button { showsGuide = true } label: {
                    Label("Set as Wallpaper", systemImage: "iphone.gen3")
                }
                .buttonStyle(KineticButtonStyle())
            } else {
                Button(action: save) {
                    Label(isSaving ? "Saving…" : "Save to Photos", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(KineticButtonStyle())
                .disabled(isSaving || filesMissing)
            }
            if !creation.isLive {
                Button { addsMotion = true } label: {
                    Label("Add Motion", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassPillButtonStyle(tint: Theme.accent))
                .disabled(filesMissing)
            }
            HStack(spacing: 12) {
                if creation.savedToPhotos {
                    Button(action: save) {
                        Label(isSaving ? "Saving…" : "Save Again", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                    }
                    .disabled(isSaving || filesMissing)
                }
                Button { confirmsDelete = true } label: {
                    Label("Delete", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassPillButtonStyle(tint: Theme.danger))
            }
            .buttonStyle(GlassPillButtonStyle())
        }
        .padding(18)
        .glass(.floating, cornerRadius: 30)
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
                saves += 1
                try? modelContext.save()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete() {
        do {
            try CreationLibrary(context: modelContext).delete(creation)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
