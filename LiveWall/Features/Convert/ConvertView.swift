import PhotosUI
import SwiftData
import SwiftUI

struct ConvertView: View {
    @State private var selection: PhotosPickerItem?
    @State private var editor: ConvertEditor?
    @State private var isImporting = false
    @State private var importError: String?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Convert")
            if let editor {
                content(for: editor)
            } else {
                emptyState
            }
        }
        #if DEBUG
        .task { await openDemoIfRequested() }
        #endif
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task { await importVideo(item) }
        }
        .alert("Couldn't open video", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    @ViewBuilder
    private func content(for editor: ConvertEditor) -> some View {
        switch editor.phase {
        case .finished(let result, let saved):
            LivePhotoResultView(editor: editor, result: result, saved: saved, onNewVideo: close)
        case .unavailable(let message):
            ContentUnavailableView {
                Label("Can't use this video", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Choose Another", action: close).buttonStyle(GlassPillButtonStyle())
            }
            .frame(maxHeight: .infinity)
        default:
            TrimStudioView(editor: editor, onClose: close)
        }
    }

    private var emptyState: some View {
        let pickerTitle = isImporting ? "Opening…" : "Choose Video"
        return ScrollView {
            VStack(spacing: 18) {
                DeviceFrame {
                    AuroraView().overlay { LockScreenOverlay(showsMotionBadge: true) }
                }
                .frame(width: 124)
                .padding(.top, 4)

                VStack(spacing: 8) {
                    Text("Video to Live Wallpaper")
                        .font(.headlineSmall)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Trim a short moment from any video and set it as a Lock Screen wallpaper that moves when you wake your iPhone.")
                        .font(.bodyMedium)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                GlassGroup(spacing: 10) {
                    HStack(spacing: 10) {
                        StepChip(number: 1, title: "Pick", symbol: "film")
                        StepChip(number: 2, title: "Trim", symbol: "timeline.selection")
                        StepChip(number: 3, title: "Set", symbol: "iphone")
                    }
                }

                PhotosPicker(selection: $selection, matching: .videos, preferredItemEncoding: .current) {
                    Label(pickerTitle, systemImage: "photo.badge.plus")
                }
                .buttonStyle(KineticButtonStyle())
                .disabled(isImporting)

                Label("Free forever · No watermark", systemImage: "checkmark.seal.fill")
                    .font(.labelMedium.weight(.semibold))
                    .foregroundStyle(Theme.cyan)
            }
            .padding(22)
            .glass(.floating, cornerRadius: 34)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func importVideo(_ item: PhotosPickerItem) async {
        isImporting = true
        defer { isImporting = false }
        do {
            guard let video = try await item.loadTransferable(type: PickedVideo.self) else {
                importError = "The selected item isn't a video."
                return
            }
            editor = ConvertEditor(sourceURL: video.url, library: CreationLibrary(context: modelContext))
        } catch {
            importError = error.localizedDescription
        }
        selection = nil
    }

    #if DEBUG
    private func openDemoIfRequested() async {
        guard editor == nil, DemoLaunch.opensEditor || DemoLaunch.opensResult,
              let url = try? await DemoVideo.make() else { return }
        let demo = ConvertEditor(sourceURL: url)
        editor = demo
        if DemoLaunch.opensResult {
            await demo.load()
            await demo.showDemoResult()
        }
    }
    #endif

    private func close() {
        editor?.stop()
        if let url = editor?.sourceURL { try? FileManager.default.removeItem(at: url) }
        editor = nil
    }
}

private struct StepChip: View {
    let number: Int
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.cyan)
            Text("\(number). \(title)")
                .font(.labelMedium.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
