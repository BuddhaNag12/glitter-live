import SwiftUI

/// Pastes a direct link to a video file and downloads it into Trim Studio.
struct LinkImportSheet: View {
    var onImport: (URL) -> Void
    /// The sheet closes first, then Convert opens the photo picker.
    var onChoosePhotos: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var progress: Double?
    @State private var isDownloading = false
    @State private var problem: String?
    @State private var guide: VideoLink.Site?
    @State private var detent = PresentationDetent.medium
    @State private var download: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Direct links to video files work, including Dropbox and Google Drive share links.")
                    .typography(.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    TextField("https://example.com/clip.mp4", text: $text)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(start)
                        .focused($isFieldFocused)
                        .typography(.bodyLarge)
                        .foregroundStyle(Theme.textPrimary)
                        .disabled(isDownloading)
                    // Reads the clipboard only when tapped, so there's no paste permission prompt.
                    PasteButton(payloadType: URL.self) { urls in
                        guard let url = urls.first else { return }
                        text = url.absoluteString
                        problem = nil
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                    .disabled(isDownloading)
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .frame(minHeight: 54)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onChange(of: text) {
                    problem = nil
                    guide = nil
                }

                if let guide {
                    SaveFirstGuide(site: guide).transition(.opacity)
                }

                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .typography(.bodyMedium)
                        .foregroundStyle(Theme.danger)
                        .transition(.opacity)
                }

                if isDownloading {
                    VStack(alignment: .leading, spacing: 8) {
                        if let progress, progress > 0 {
                            ProgressView(value: progress)
                            Text("Downloading… \(progress, format: .percent.precision(.fractionLength(0)))")
                        } else {
                            ProgressView()
                            Text("Connecting…")
                        }
                    }
                    .typography(.labelMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .tint(Theme.accent)
                    .transition(.opacity)
                }

                Spacer(minLength: 0)

                if guide != nil {
                    Button(action: onChoosePhotos) {
                        Label("Choose from Photos", systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(KineticButtonStyle())
                } else {
                    Button(action: start) {
                        Label("Download Video", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(KineticButtonStyle())
                    .disabled(isDownloading || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .animation(.easeOut(duration: 0.2), value: problem)
            .animation(.easeOut(duration: 0.2), value: guide)
            .animation(.easeOut(duration: 0.2), value: isDownloading)
            .navigationTitle("Paste a video link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        download?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        // The steps need the room, and a cut-off step is worse than a taller sheet.
        .onChange(of: guide) { _, guide in if guide != nil { detent = .large } }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isDownloading)
        .onAppear { isFieldFocused = true }
    }

    private func start() {
        guard !isDownloading else { return }
        let url: URL
        do {
            url = try VideoLink.url(from: text)
        } catch {
            isFieldFocused = false
            if case .videoSite(let site) = error { guide = site } else { problem = error.localizedDescription }
            return
        }
        isFieldFocused = false
        isDownloading = true
        progress = nil
        download = Task {
            defer { isDownloading = false }
            do {
                let file = try await VideoLink.download(url) { fraction in
                    Task { @MainActor in progress = fraction }
                }
                onImport(file)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}

/// Instead of a dead end: how to save the video from the site's own app, which is allowed, and bring it in from Photos.
private struct SaveFirstGuide: View {
    let site: VideoLink.Site

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save it from \(site.name) first")
                .typography(.titleMedium)
                .foregroundStyle(Theme.textPrimary)
            ForEach(Array(site.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.labelMedium.weight(.bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 22, height: 22)
                        .background(Theme.accentFill, in: Circle())
                    Text(step)
                        .typography(.bodyMedium)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let note = site.note {
                Text(note)
                    .typography(.labelMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
