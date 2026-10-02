import PhotosUI
import SwiftUI

struct LivePhotoResultView: View {
    let editor: ConvertEditor
    let result: LivePhotoResult
    let saved: Bool
    var labels = Labels()
    var onNewVideo: () -> Void

    struct Labels {
        var save = "Save to Photos"
        var edit = "Edit Again"
        var new = "New Video"
        var newSymbol = "plus"
    }

    @State private var livePhoto: PHLivePhoto?
    @State private var isSaving = false
    @State private var showsGuide = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                StatusPill(
                    text: saved ? "SAVED TO PHOTOS" : "LIVE PHOTO READY",
                    dot: saved ? Theme.accent : Theme.signalYellow,
                    highlighted: saved,
                    symbol: saved ? "checkmark" : nil
                )
                .padding(.top, 10)

                DeviceFrame {
                    LivePhotoView(livePhoto: livePhoto)
                        .overlay { LockScreenOverlay() }
                        .overlay(alignment: .topLeading) {
                            StatusPill(text: "LIVE", dot: Theme.signalYellow).padding(12)
                        }
                }
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.47 }

                Label("Touch and hold the preview to play it", systemImage: "hand.tap")
                    .font(.labelMedium)
                    .foregroundStyle(Theme.textSecondary)

                VStack(spacing: 14) {
                    if saved {
                        Button {
                            showsGuide = true
                        } label: {
                            Label("Set as Wallpaper", systemImage: "iphone.gen3")
                        }
                        .buttonStyle(KineticButtonStyle())
                    } else {
                        Button {
                            Task {
                                isSaving = true
                                await editor.save(result)
                                isSaving = false
                            }
                        } label: {
                            Label(isSaving ? "Saving…" : labels.save, systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(KineticButtonStyle())
                        .disabled(isSaving)
                    }
                    HStack(spacing: 12) {
                        Button(action: editor.returnToEditing) {
                            Label(labels.edit, systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                        }
                        Button(action: onNewVideo) {
                            Label(labels.new, systemImage: labels.newSymbol).frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
                .padding(18)
                .glass(.floating, cornerRadius: 30)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .task(id: result) {
            livePhoto = try? await LivePhotoLoader.load(result)
        }
        .sheet(isPresented: $showsGuide) {
            SetWallpaperGuideView()
                .presentationDetents([.medium, .large])
        }
        .alert("Couldn't save", isPresented: .constant(editor.errorMessage != nil)) {
            Button("OK") { editor.errorMessage = nil }
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }
}
