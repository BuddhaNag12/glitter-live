import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsGuide = false
    @AppStorage(OnboardingState.completedKey) private var hasCompletedOnboarding = true

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "livephoto")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 50, height: 50)
                            .liquidGlass(in: Circle(), tint: Theme.accent.opacity(0.2))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Converting is free").font(.titleMedium).foregroundStyle(Theme.textPrimary)
                            Text("Turn as many videos into live wallpapers as you like. No watermark, no account.")
                                .font(.labelMedium)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(.floating, cornerRadius: 24)

                    VStack(spacing: 0) {
                        row("How to set a live wallpaper", symbol: "iphone.gen3") { showsGuide = true }
                        Divider().overlay(Theme.stroke)
                        row("Show intro again", symbol: "sparkles.rectangle.stack") {
                            dismiss()
                            // The intro is a full-screen cover, which can't appear until this sheet has gone.
                            Task {
                                try? await Task.sleep(for: .milliseconds(450))
                                hasCompletedOnboarding = false
                            }
                        }
                        Divider().overlay(Theme.stroke)
                        NavigationLink {
                            AcknowledgementsView()
                        } label: {
                            rowLabel("Acknowledgements", symbol: "doc.text")
                        }
                    }
                    .glass(.surface, cornerRadius: 22)

                    Text("Glitter Live \(version)")
                        .font(.labelMedium)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .background { AppBackground() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showsGuide) {
            SetWallpaperGuideView().presentationDetents([.medium, .large])
        }
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, symbol: symbol) }
    }

    private func rowLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 24)
            Text(title).font(.bodyLarge).foregroundStyle(Theme.textPrimary)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

private struct AcknowledgementsView: View {
    private let text: String = {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()

    var body: some View {
        ScrollView {
            Text(text)
                .font(.labelMedium.monospaced())
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .padding(16)
        }
        .background { AppBackground() }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
