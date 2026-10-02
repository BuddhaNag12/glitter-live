import PhotosUI
import SwiftData
import SwiftUI

struct ConvertView: View {
    @State private var selection: PhotosPickerItem?
    @State private var editor: ConvertEditor?
    @State private var isImporting = false
    @State private var importError: String?
    @State private var choosesFile = false
    @State private var pastesLink = false
    @State private var choosesPhoto = false
    @State private var opensPhotosAfterLink = false
    @State private var showsShareTip = false
    @Environment(\.modelContext) private var modelContext
    @Environment(ConversionAllowance.self) private var conversions
    @Environment(Purchases.self) private var purchases
    @Environment(IncomingVideo.self) private var incoming
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Stage { case pick, edit, result, unavailable }

    private var stage: Stage {
        switch editor?.phase {
        case nil: .pick
        case .finished: .result
        case .unavailable: .unavailable
        default: .edit
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let editor {
                ConvertFlowView(editor: editor, onClose: close)
            } else {
                emptyState.transition(.screen(reduceMotion: reduceMotion))
            }
        }
        .animation(.spring(duration: 0.4), value: stage)
        .screenHeader("Convert")
        .sensoryFeedback(trigger: editor?.phase) { _, phase in
            if case .finished(_, saved: true) = phase { .success } else { nil }
        }
        // Export and save failures both surface as an error message.
        .sensoryFeedback(.error, trigger: editor?.errorMessage) { _, message in message != nil }
        .sensoryFeedback(.error, trigger: importError) { _, message in message != nil }
        #if DEBUG
        .task { await openDemoIfRequested() }
        #endif
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task { await importVideo(item) }
        }
        .onChange(of: incoming.url, initial: true) { _, url in
            guard let url else { return }
            incoming.url = nil
            open(url)
        }
        .fileImporter(isPresented: $choosesFile, allowedContentTypes: [.movie]) { result in
            Task { await importFile(result) }
        }
        .sheet(isPresented: $pastesLink, onDismiss: openPhotosIfRequested) {
            LinkImportSheet(onImport: open) {
                opensPhotosAfterLink = true
                pastesLink = false
            }
        }
        .photosPicker(isPresented: $choosesPhoto, selection: $selection, matching: .videos, preferredItemEncoding: .current)
        .purchaseMessages(purchases)
        .alert("Couldn't open video", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    /// One screen with no scrolling: the free count, a compact preview, then the sources within thumb reach.
    private var emptyState: some View {
        let pickerTitle = isImporting ? "Opening…" : "Choose from Photos"
        return GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    AllowanceBadge(access: conversions.access)
                    Spacer(minLength: 0)
                    // Short screens such as the iPhone SE drop the steps and shrink the phone, so the buttons stay in view.
                    hero(isShort: geometry.size.height < 600)
                    Spacer(minLength: 12)
                    VStack(spacing: 12) {
                        PhotosPicker(selection: $selection, matching: .videos, preferredItemEncoding: .current) {
                            Label(pickerTitle, systemImage: "photo.badge.plus")
                        }
                        .buttonStyle(KineticButtonStyle())
                        otherSources
                        if conversions.access == .ad {
                            Button(purchases.unlockTitle, systemImage: "infinity") {
                                Task { await purchases.buyUnlimitedConversions() }
                            }
                            .buttonStyle(GlassPillButtonStyle(tint: Theme.accent))
                            .disabled(purchases.isPurchasing)
                        }
                    }
                    .disabled(isImporting)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .alert("Share from an App", isPresented: $showsShareTip) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("In Photos, Files, WhatsApp or any app, tap Share on a video and choose Glitter Live. If it isn't listed, tap More and turn it on.")
        }
    }

    private func hero(isShort: Bool) -> some View {
        // Side by side normally; stacked at accessibility sizes, where the text column would break mid-word.
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let layout = isStacked ? AnyLayout(VStackLayout(spacing: 18)) : AnyLayout(HStackLayout(spacing: 18))
        return layout {
            DeviceFrame {
                AuroraView().overlay { LockScreenOverlay(showsMotionBadge: true) }
            }
            .frame(width: isStacked ? 120 : isShort ? 100 : 140)
            VStack(alignment: .leading, spacing: 10) {
                Text("Video to Live Wallpaper")
                    .typography(.headlineSmall)
                    .foregroundStyle(Theme.textPrimary)
                Text("Trim a moment from any video. It moves each time you wake your iPhone.")
                    .typography(.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !isShort {
                    VStack(alignment: .leading, spacing: 8) {
                        MiniStep(number: 1, text: "Pick a video")
                        MiniStep(number: 2, text: "Trim 1–3 seconds")
                        MiniStep(number: 3, text: "Set it from Photos")
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .glass(.floating, cornerRadius: 30)
    }

    /// The less common sources wait in a menu, so Photos stays the obvious first choice.
    private var otherSources: some View {
        Menu {
            Button("Files", systemImage: "folder") { choosesFile = true }
            Button("Paste Link", systemImage: "link") { pastesLink = true }
            Divider()
            Button("Share from an App", systemImage: "square.and.arrow.up") { showsShareTip = true }
        } label: {
            Label("Other Sources", systemImage: "ellipsis.circle")
                .frame(maxWidth: .infinity)
        }
        .menuStyle(.button)
        .buttonStyle(GlassPillButtonStyle())
    }

    /// Two sheets can't be up at once, so the picker waits for the link sheet to go.
    private func openPhotosIfRequested() {
        guard opensPhotosAfterLink else { return }
        opensPhotosAfterLink = false
        choosesPhoto = true
    }

    /// Opens a video the app already holds a copy of, replacing anything left in Trim Studio.
    private func open(_ url: URL) {
        close()
        editor = ConvertEditor(sourceURL: url, library: CreationLibrary(context: modelContext), allowance: conversions)
    }

    private func importFile(_ result: Result<URL, any Error>) async {
        isImporting = true
        defer { isImporting = false }
        do {
            open(try await ImportedVideos.copy(result.get()))
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importVideo(_ item: PhotosPickerItem) async {
        isImporting = true
        defer { isImporting = false }
        do {
            guard let video = try await item.loadTransferable(type: PickedVideo.self) else {
                importError = "The selected item isn't a video."
                return
            }
            open(video.url)
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

/// Trim Studio, then the result, for a video that's been picked or generated.
struct ConvertFlowView: View {
    let editor: ConvertEditor
    var labels = LivePhotoResultView.Labels()
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch editor.phase {
        case .finished(let result, let saved):
            LivePhotoResultView(editor: editor, result: result, saved: saved, labels: labels, onNewVideo: onClose)
                .transition(.screen(reduceMotion: reduceMotion))
        case .unavailable(let message):
            ContentUnavailableView {
                Label("Can't use this video", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Choose Another", action: onClose).buttonStyle(GlassPillButtonStyle())
            }
            .frame(maxHeight: .infinity)
            .transition(.screen(reduceMotion: reduceMotion))
        default:
            TrimStudioView(editor: editor, onClose: onClose)
                .transition(.screen(reduceMotion: reduceMotion))
        }
    }
}

/// How the next save is paid for, so an ad never comes as a surprise.
private struct AllowanceBadge: View {
    let access: ConversionAllowance.Access

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.labelMedium.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .liquidGlass(in: Capsule(), tint: Theme.accent.opacity(0.16))
            .contentTransition(.numericText())
            .animation(.spring(duration: 0.3), value: access)
    }

    private var text: String {
        switch access {
        case .unlimited: "Free · No watermark"
        case .free(let remaining): "\(remaining) of \(ConversionAllowance.freeConversions) free left · No watermark"
        case .ad: "Free with a short ad · No watermark"
        case .unlocked: "Unlimited · No watermark"
        }
    }

    private var symbol: String {
        switch access {
        case .unlimited, .unlocked: "checkmark.seal.fill"
        case .free: "gift.fill"
        case .ad: "play.rectangle.fill"
        }
    }
}

private struct MiniStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.labelSmall)
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .frame(width: 20, height: 20)
                .background(Theme.accent.opacity(0.16), in: Circle())
            Text(text)
                .font(.labelMedium.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}
