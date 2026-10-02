import SwiftData
import SwiftUI

/// Brings a saved still to life with the same free depth motion as Create, then offers it as a Live wallpaper.
struct AddMotionView: View {
    let imageURL: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var editor: ConvertEditor?
    @State private var isReady = false
    @State private var image: UIImage?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let editor, isReady {
                ConvertFlowView(
                    editor: editor,
                    labels: .init(save: "Save Live Wallpaper", edit: "Edit Motion", new: "Done", newSymbol: "checkmark"),
                    onClose: close
                )
            } else {
                progress
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AppBackground(twinkles: false) }
        .sensoryFeedback(trigger: editor?.phase) { _, phase in
            if case .finished(_, saved: true) = phase { .success } else { nil }
        }
        .task { await makeLive() }
        .alert("Couldn't add motion", isPresented: .constant(errorMessage != nil)) {
            Button("OK", action: close)
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var progress: some View {
        VStack(spacing: 22) {
            DeviceFrame {
                Theme.lockScreen
                    .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
                    .clipped()
                    .shimmer()
                    .overlay { LockScreenOverlay() }
            }
            .frame(width: 190)
            VStack(spacing: 6) {
                Text("Adding motion").typography(.headlineSmall).foregroundStyle(Theme.textPrimary)
                Text("Turning it into a 3-second loop.").typography(.bodyMedium).foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func makeLive() async {
        image = UIImage(contentsOfFile: imageURL.path(percentEncoded: false))
        do {
            // Depth motion only: AI motion needs the prompt, which a saved still no longer has.
            let video = try await DepthMotionService().animate(imageAt: imageURL, for: GenerationRequest(prompt: "", style: .cinematic))
            let editor = ConvertEditor(sourceURL: video, library: CreationLibrary(context: modelContext))
            await editor.load()
            self.editor = editor
            await editor.export(savesToPhotos: false)
            isReady = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func close() {
        editor?.stop()
        if let url = editor?.sourceURL { try? FileManager.default.removeItem(at: url) }
        dismiss()
    }
}
