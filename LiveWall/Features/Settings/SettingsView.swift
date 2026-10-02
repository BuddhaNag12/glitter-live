import SwiftUI

/// Public pages for the App Store listing and Settings. They're served from the repository's docs folder.
enum AppLinks {
    static let privacyPolicy = URL(string: "https://github.com/BuddhaNag12/glitter-live/blob/main/docs/privacy.md")!
    static let support = URL(string: "https://github.com/BuddhaNag12/glitter-live/blob/main/docs/support.md")!
}

struct SettingsView: View {
    var onShowIntro: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(ConversionAllowance.self) private var conversions
    @Environment(Purchases.self) private var purchases
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
                    if conversions.access != .unlimited {
                        purchaseRows.glass(.surface, cornerRadius: 22)
                    }

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

                    VStack(spacing: 0) {
                        Link(destination: AppLinks.support) {
                            rowLabel("Support", symbol: "questionmark.circle", opensWeb: true)
                        }
                        Divider().overlay(Theme.stroke)
                        Link(destination: AppLinks.privacyPolicy) {
                            rowLabel("Privacy Policy", symbol: "hand.raised", opensWeb: true)
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
        .purchaseMessages(purchases)
    }

    private var purchaseRows: some View {
        VStack(spacing: 0) {
            if conversions.access == .unlocked {
                rowLabel("Unlimited conversions", symbol: "checkmark.seal.fill", detail: "Unlocked")
            } else {
                row("Unlock unlimited conversions", symbol: "lock.open", detail: purchases.unlimitedConversions?.displayPrice) {
                    Task { await purchases.buyUnlimitedConversions() }
                }
                .disabled(purchases.isPurchasing)
            }
            Divider().overlay(Theme.stroke)
            row("Restore purchases", symbol: "arrow.clockwise") {
                Task { await purchases.restore() }
            }
            #if DEBUG
            Divider().overlay(Theme.stroke)
            row("Reset free conversions", symbol: "hammer", detail: "\(conversions.freeUsed) used", action: conversions.reset)
            #endif
        }
    }

    private func row(_ title: String, symbol: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, symbol: symbol, detail: detail) }
    }

    /// Rows that leave the app end in an outward arrow instead of a chevron; rows with a detail show it instead.
    private func rowLabel(_ title: String, symbol: String, opensWeb: Bool = false, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 24)
            Text(title).typography(.bodyLarge).foregroundStyle(Theme.textPrimary)
            Spacer()
            if let detail {
                Text(detail).typography(.bodyMedium).foregroundStyle(Theme.textSecondary)
            } else {
                Image(systemName: opensWeb ? "arrow.up.forward" : "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
            }
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
