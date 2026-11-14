import SwiftUI

/// The generated still on a Lock Screen preview: save it as is, or bring it to life first.
struct GeneratedImageView: View {
    let model: CreateModel
    let imageURL: URL
    let library: CreationLibrary

    @State private var image: UIImage?
    @State private var isSaving = false
    @State private var showsGuide = false
    @State private var showsReportReasons = false
    @State private var isReported = false
    @State private var showsFullScreen = false
    @State private var viewerID = UUID()
    @Namespace private var zoom

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                StatusPill(
                    text: model.savedStill ? "SAVED TO PHOTOS" : "YOUR WALLPAPER",
                    dot: model.savedStill ? Theme.accent : Theme.signalYellow,
                    highlighted: model.savedStill,
                    symbol: model.savedStill ? "checkmark" : nil
                )
                .padding(.top, 10)

                DeviceFrame {
                    Theme.lockScreen
                        // An overlay takes the frame's size, so the square image is cropped to the screen's shape.
                        .overlay {
                            if let image { Image(uiImage: image).resizable().scaledToFill() }
                        }
                        .clipped()
                        .overlay { LockScreenOverlay() }
                }
                // Small enough that every action fits above the tab bar without scrolling.
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.4 }
                .zoomSource(id: viewerID, in: zoom, cornerRadius: 24)
                // Tap for the full-screen Lock Screen view, as in Explore and the Library.
                .onTapGesture { showsFullScreen = true }
                .accessibilityLabel("Generated wallpaper: \(model.prompt)")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Shows it full screen")

                VStack(spacing: 10) {
                    Button(action: saveOrShowGuide) {
                        Label(saveTitle, systemImage: model.savedStill ? "iphone.gen3" : "square.and.arrow.down")
                    }
                    .buttonStyle(KineticButtonStyle())
                    .disabled(isSaving)

                    Button {
                        Task { await model.addMotion(library: library) }
                    } label: {
                        Label("Add Motion", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassPillButtonStyle(tint: Theme.accent))

                    HStack(spacing: 12) {
                        Button {
                            Task { await model.generate() }
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                        }
                        .disabled(!model.canGenerate)
                        // Back to the description, kept so it can be changed, for a new image.
                        Button(action: model.editPrompt) {
                            Label("New Image", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
                .padding(16)
                .glass(.floating, cornerRadius: 30)

                Button(isReported ? "Reported" : "Report This Image", systemImage: isReported ? "checkmark" : "flag") {
                    showsReportReasons = true
                }
                .font(.labelMedium)
                .foregroundStyle(Theme.textSecondary)
                .disabled(isReported)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .task(id: imageURL) {
            isReported = false
            image = UIImage(contentsOfFile: imageURL.path(percentEncoded: false))
        }
        .confirmationDialog("What's wrong with this image?", isPresented: $showsReportReasons, titleVisibility: .visible) {
            ForEach(GenerationReport.Reason.allCases) { reason in
                Button(reason.title) {
                    Task { isReported = await model.report(reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your description is sent with the report so we can improve the filters. The image isn't.")
        }
        .sheet(isPresented: $showsGuide) {
            SetWallpaperGuideView(isLive: false)
        }
        .fullScreenCover(isPresented: $showsFullScreen) {
            LockScreenViewer(
                items: [ViewerItem(id: viewerID, title: "Your wallpaper", isLive: false, image: imageURL)],
                startingAt: viewerID
            ) { _ in
                SaveIconButton(
                    phase: isSaving ? .working : model.savedStill ? .saved : .ready,
                    label: model.savedStill ? "Saved to Photos. How to set it as your wallpaper" : "Save Wallpaper",
                    action: saveOrShowGuide
                )
            }
            .sheet(isPresented: $showsGuide) { SetWallpaperGuideView(isLive: false) }
            .zoomTransition(from: viewerID, in: zoom)
        }
    }

    private func saveOrShowGuide() {
        if model.savedStill {
            showsGuide = true
        } else {
            Task {
                isSaving = true
                await model.saveStill(library: library)
                isSaving = false
            }
        }
    }

    private var saveTitle: String {
        if model.savedStill { return "Set as Wallpaper" }
        return isSaving ? "Saving…" : "Save Wallpaper"
    }
}
