import SwiftUI

/// Shown once the free conversions are used up: a short ad saves this video, or the one-time purchase removes the limit.
struct UnlockConversionsSheet: View {
    enum Choice { case ad, unlocked }

    var onChoose: (Choice) -> Void

    @Environment(Purchases.self) private var purchases
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("Save this live wallpaper")
                        .typography(.headlineSmall)
                        .foregroundStyle(Theme.textPrimary)
                    Text("You've used your \(ConversionAllowance.freeConversions) free conversions.")
                        .typography(.bodyMedium)
                        .foregroundStyle(Theme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

                OptionCard(symbol: "play.rectangle.fill", title: "Watch a short ad", detail: "Free · saves this one") {
                    onChoose(.ad)
                } trailing: {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }

                OptionCard(symbol: "infinity", title: "Unlimited conversions", detail: "No ads, ever · pay once", isHighlighted: true) {
                    Task { if await purchases.buyUnlimitedConversions() { onChoose(.unlocked) } }
                } trailing: {
                    if purchases.isPurchasing {
                        ProgressView().tint(Theme.accent)
                    } else if let price = purchases.unlimitedConversions?.displayPrice {
                        Text(price)
                            .typography(.labelLarge)
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Theme.accentFill, in: Capsule())
                    }
                }
                .disabled(purchases.isPurchasing)

                Button("Restore Purchase") {
                    Task {
                        await purchases.restore()
                        guard purchases.ownsUnlimitedConversions else { return }
                        // Going straight on says it worked; an alert would only be in the way.
                        purchases.message = nil
                        onChoose(.unlocked)
                    }
                }
                .font(.labelMedium.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(390)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .purchaseMessages(purchases)
        .task { if purchases.unlimitedConversions == nil { await purchases.load() } }
    }
}

private struct OptionCard<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: String
    var isHighlighted = false
    var action: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .scaledIcon(size: 18, weight: .semibold, frame: 44)
                    .foregroundStyle(Theme.accent)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).typography(.titleMedium).foregroundStyle(Theme.textPrimary)
                    Text(detail).typography(.bodyMedium).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isHighlighted ? Theme.accentFill : Theme.border, lineWidth: isHighlighted ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
