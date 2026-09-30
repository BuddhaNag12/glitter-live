import SwiftUI

struct SettingsView: View {
    var onShowIntro: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var showsGuide = false

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
                    VStack(spacing: 0) {
                        row("How to set a live wallpaper", symbol: "iphone.gen3") { showsGuide = true }
                        Divider().overlay(Theme.stroke)
                        row("Show intro again", symbol: "sparkles.rectangle.stack") {
                            onShowIntro()
                            dismiss()
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
            Text(title).typography(.bodyLarge).foregroundStyle(Theme.textPrimary)
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
