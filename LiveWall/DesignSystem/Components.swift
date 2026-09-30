import SwiftUI

// MARK: - Liquid Glass

extension View {
    /// Apple's Liquid Glass on iOS 26+, frosted material with a specular rim before that.
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill((tint ?? Theme.surface).opacity(0.35)))
                    .overlay(shape.strokeBorder(Theme.specularRim, lineWidth: 1))
            }
        }
    }

    /// Glass card or panel from the design system's depth tiers.
    func glass(_ tier: GlassTier = .surface, cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassPanel(tier: tier, cornerRadius: cornerRadius))
    }
}

/// Lets neighbouring glass shapes blend and morph into each other on iOS 26+.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

enum GlassTier {
    /// Cards and shelves.
    case surface
    /// Floating panels, scrubbers and bars.
    case floating
}

private struct GlassPanel: ViewModifier {
    var tier: GlassTier
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .liquidGlass(in: shape, tint: tier == .surface ? Theme.surface.opacity(0.5) : Theme.card.opacity(0.6))
            .overlay(shape.strokeBorder(Theme.specularRim, lineWidth: 0.75).allowsHitTesting(false))
            .shadow(color: .black.opacity(tier == .floating ? 0.4 : 0), radius: 18, y: 14)
    }
}

// MARK: - Buttons

/// The gradient call to action. Kept opaque so it reads as the one primary action on a glass screen.
struct KineticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KineticButton(configuration: configuration)
    }

    private struct KineticButton: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            configuration.label
                .font(.inter(18, .semibold, relativeTo: .headline))
                .foregroundStyle(Theme.base)
                .frame(maxWidth: .infinity, minHeight: 58)
                .padding(.horizontal, 16)
                .background(Theme.action, in: shape)
                .overlay(alignment: .top) {
                    // Specular highlight along the top edge.
                    shape
                        .fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
                        .blendMode(.softLight)
                }
                .overlay(shape.strokeBorder(.white.opacity(0.45), lineWidth: 1))
                .shadow(color: Theme.cyan.opacity(configuration.isPressed ? 0.55 : 0.28), radius: configuration.isPressed ? 24 : 16, y: 6)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.spring(duration: 0.25), value: configuration.isPressed)
        }
    }
}

struct GlassPillButtonStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.labelMedium.weight(.semibold))
            .foregroundStyle(tint ?? Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .liquidGlass(in: Capsule(), tint: tint?.opacity(0.18), interactive: true)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: size, height: size)
            .liquidGlass(in: Circle(), interactive: true)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Compact cyan capsule, as used for "Save" in the Trim Studio toolbar.
struct AccentCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AccentCapsule(configuration: configuration)
    }

    private struct AccentCapsule: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.titleMedium)
                .foregroundStyle(Theme.base)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Theme.cyan, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                .shadow(color: Theme.cyan.opacity(0.45), radius: 14)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.spring(duration: 0.2), value: configuration.isPressed)
        }
    }
}

// MARK: - Pills and headers

struct StatusPill: View {
    let text: String
    var dot: Color = Theme.cyan
    var highlighted = false
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(dot)
            } else {
                Circle()
                    .fill(dot)
                    .frame(width: 7, height: 7)
                    .shadow(color: dot.opacity(0.9), radius: 4)
            }
            Text(text)
                .font(.labelSmall)
                .tracking(0.6)
                .foregroundStyle(highlighted ? Theme.cyan : Theme.textPrimary)
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .liquidGlass(in: Capsule(), tint: highlighted ? Theme.cyan.opacity(0.22) : nil)
        .overlay(Capsule().strokeBorder(highlighted ? Theme.cyan.opacity(0.4) : .clear, lineWidth: 1))
    }
}

struct ScreenHeader: View {
    let title: String
    @Environment(\.showSettings) private var showSettings

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.displayLarge)
                    .tracking(-0.8)
                    .foregroundStyle(Theme.textPrimary)
                StatusPill(text: "LIVE", highlighted: true)
                Spacer()
                Button(action: showSettings.callAsFunction) {
                    Image(systemName: "person")
                }
                .buttonStyle(CircleIconButtonStyle())
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16)
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Theme.strokeHighlight, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .padding(.top, 8)
    }
}

struct SettingsAction {
    var action: @MainActor () -> Void = {}
    @MainActor func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var showSettings = SettingsAction()
}
