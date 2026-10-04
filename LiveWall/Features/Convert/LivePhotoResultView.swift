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
    /// Height of everything except the phone, so the phone can take what's left of the screen.
    @State private var chromeHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content(phoneWidth: phoneWidth(in: geometry.size))
                    .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .task(id: result) {
            livePhoto = try? await LivePhotoLoader.load(result)
        }
        .sheet(isPresented: $showsGuide) {
            SetWallpaperGuideView()
        }
        .alert("Couldn't save", isPresented: .constant(editor.errorMessage != nil)) {
            Button("OK") { editor.errorMessage = nil }
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }

    /// Short screens such as the iPhone SE shrink the phone so the buttons stay above the tab bar.
    /// Larger text can still push past the screen, and then it scrolls.
    private func phoneWidth(in size: CGSize) -> CGFloat {
        let fittingWidth = (size.height - chromeHeight) * WallpaperFormat.aspectRatio
        return max(min(size.width * 0.47, fittingWidth), 90)
    }

    private func content(phoneWidth: CGFloat) -> some View {
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
                        // On a phone this narrow the badge would cover the date.
                        if phoneWidth >= 150 {
                            StatusPill(text: "LIVE", dot: Theme.signalYellow).padding(12)
                        }
                    }
            }
            .frame(width: phoneWidth)

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
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeHeight = $0 - phoneWidth / WallpaperFormat.aspectRatio }
    }
}
