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
            .liquidGlass(in: shape, tint: tier == .surface ? Theme.surface.opacity(0.6) : Theme.elevated.opacity(0.6))
            .overlay(shape.strokeBorder(Theme.specularRim, lineWidth: 0.75).allowsHitTesting(false))
            .shadow(color: .black.opacity(tier == .floating ? 0.12 : 0), radius: 16, y: 8)
    }
}

// MARK: - Buttons

/// The primary call to action: the blue-to-slate brand gradient with a slow silver shine sweeping across.
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
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 58)
                .padding(.horizontal, 16)
                .background(Theme.accentGradient, in: shape)
                .overlay { if isEnabled { ShimmerSweep().clipShape(shape) } }
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

/// Compact blue capsule, as used for "Save" in the Trim Studio toolbar.
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
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Theme.accentGradient, in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.spring(duration: 0.2), value: configuration.isPressed)
        }
    }
}

/// A soft band of light that glides across a surface every few seconds. Hidden with Reduce Motion.
struct ShimmerSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let period = 4.5
    private let travel = 1.2

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                GeometryReader { geometry in
                    let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / travel
                    let band = geometry.size.width * 0.35
                    LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: band)
                        .rotationEffect(.degrees(18))
                        .offset(x: -band + (geometry.size.width + band * 2) * min(progress, 1))
                        .opacity(progress <= 1 ? 1 : 0)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Pills and headers

struct StatusPill: View {
    let text: String
    var dot: Color = Theme.accent
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
            }
            Text(text)
                .font(.labelSmall)
                .tracking(0.6)
                .foregroundStyle(highlighted ? Theme.accent : Theme.textPrimary)
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .liquidGlass(in: Capsule(), tint: highlighted ? Theme.accent.opacity(0.22) : nil)
        .overlay(Capsule().strokeBorder(highlighted ? Theme.accent.opacity(0.4) : .clear, lineWidth: 1))
    }
}

struct ScreenHeader: View {
    let title: String
    @Environment(\.showSettings) private var showSettings

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                // The tab bar already shows which screen this is, so the header carries the brand.
                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
                    .accessibilityElement()
                    .accessibilityLabel("Glitter Live, \(title)")
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: showSettings.callAsFunction) {
                    Image(systemName: "person")
                }
                .buttonStyle(CircleIconButtonStyle())
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16)
            Rectangle()
                .fill(Theme.border)
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
