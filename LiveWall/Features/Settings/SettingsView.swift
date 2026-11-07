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
                VStack(alignment: .leading, spacing: 8) {
                    if conversions.access != .unlimited {
                        sectionHeader("Upgrade")
                        upgradeCard
                        purchaseRows.glass(.surface, cornerRadius: 22).padding(.top, 4)
                    }

                    sectionHeader("Help")
                    VStack(spacing: 0) {
                        row("How to set a live wallpaper", symbol: "iphone.gen3", tint: WallpaperPalette.blue) { showsGuide = true }
                        rowDivider
                        row("Show intro again", symbol: "sparkles.rectangle.stack", tint: WallpaperPalette.violet) {
                            onShowIntro()
                            dismiss()
                        }
                        rowDivider
                        Link(destination: AppLinks.support) {
                            rowLabel("Support", symbol: "questionmark", tint: WallpaperPalette.sky, opensWeb: true)
                        }
                    }
                    .glass(.surface, cornerRadius: 22)

                    sectionHeader("About")
                    VStack(spacing: 0) {
                        NavigationLink {
                            AcknowledgementsView()
                        } label: {
                            rowLabel("Acknowledgements", symbol: "doc.text", tint: Theme.slate)
                        }
                        rowDivider
                        Link(destination: AppLinks.privacyPolicy) {
                            rowLabel("Privacy Policy", symbol: "hand.raised.fill", tint: WallpaperPalette.indigo, opensWeb: true)
                        }
                    }
                    .glass(.surface, cornerRadius: 22)

                    Text("Glitter Live \(version)")
                        .font(.labelMedium)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
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
            SetWallpaperGuideView()
        }
        .purchaseMessages(purchases)
        // Settings is a sheet, which would hide the app's own celebration behind it.
        .unlockCelebration(count: purchases.unlockCount)
    }

    /// The unlock offer leads the page as its own panel, with the price on a capsule like a buy button.
    @ViewBuilder
    private var upgradeCard: some View {
        if conversions.access == .unlocked {
            rowLabel("Unlimited conversions", symbol: "checkmark.seal.fill", tint: WallpaperPalette.amber, detail: "Unlocked")
                .glass(.surface, cornerRadius: 22)
        } else {
            Button {
                Task { await purchases.buyUnlimitedConversions() }
            } label: {
                HStack(spacing: 12) {
                    tile("lock.open.fill", tint: WallpaperPalette.amber, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlimited conversions").typography(.titleMedium).foregroundStyle(Theme.textPrimary)
                        Text("Turn as many videos into wallpapers as you like.").typography(.bodyMedium).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(purchases.unlimitedConversions?.displayPrice ?? "Unlock")
                        .typography(.labelLarge)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Theme.accentGradient, in: Capsule())
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(purchases.isPurchasing)
            .glass(.floating, cornerRadius: 22)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Unlock unlimited conversions, \(purchases.unlimitedConversions?.displayPrice ?? "")")
        }
    }

    private var purchaseRows: some View {
        VStack(spacing: 0) {
            row("Restore purchases", symbol: "arrow.clockwise", tint: WallpaperPalette.teal) {
                Task { await purchases.restore() }
            }
            if RewardedAds.shared.offersPrivacyChoices {
                rowDivider
                row("Ad privacy choices", symbol: "hand.raised.square.fill", tint: WallpaperPalette.indigo) {
                    Task { await RewardedAds.shared.showPrivacyChoices() }
                }
            }
            #if DEBUG
            rowDivider
            row("Reset free conversions", symbol: "hammer.fill", tint: Theme.slate, detail: "\(conversions.freeUsed) used", action: conversions.reset)
            rowDivider
            row("Preview unlock celebration", symbol: "party.popper.fill", tint: WallpaperPalette.rose, action: purchases.previewUnlockCelebration)
            #endif
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.labelSmall)
            .tracking(1)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .accessibilityAddTraits(.isHeader)
    }

    /// Starts under the row titles, past the icon tiles, as in iOS Settings.
    private var rowDivider: some View {
        Divider().overlay(Theme.stroke).padding(.leading, 58)
    }

    /// A white symbol on a coloured rounded square, so each row is recognisable at a glance.
    private func tile(_ symbol: String, tint: Color, size: CGFloat = 30) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.47, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }

    private func row(_ title: String, symbol: String, tint: Color, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, symbol: symbol, tint: tint, detail: detail) }
    }

    /// Rows that leave the app end in an outward arrow instead of a chevron; rows with a detail show it instead.
    private func rowLabel(_ title: String, symbol: String, tint: Color, opensWeb: Bool = false, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            tile(symbol, tint: tint)
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
