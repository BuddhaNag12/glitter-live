import SwiftUI

// MARK: - Liquid Glass

extension View {
    /// Apple's Liquid Glass on iOS 26+, frosted material with a specular rim before that.
    /// On top of another glass surface it becomes a tinted fill, because glass on glass loses legibility.
    /// With Increase Contrast it becomes a near-solid surface with a defined border.
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlass(shape: shape, tint: tint, interactive: interactive))
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

extension EnvironmentValues {
    /// True inside a glass surface, so nested elements draw as fills instead of more glass.
    @Entry var isOnGlass = false
}

private struct LiquidGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.isOnGlass) private var isOnGlass
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let increasedContrast = contrast == .increased
        if isOnGlass {
            content
                .background(tint ?? Theme.fill, in: shape)
                .overlay { if increasedContrast { shape.strokeBorder(Theme.border, lineWidth: 1).allowsHitTesting(false) } }
        } else if increasedContrast {
            content
                .environment(\.isOnGlass, true)
                .background {
                    shape
                        .fill(Theme.surface)
                        .overlay(shape.fill(tint ?? .clear))
                        .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
                }
        } else if #available(iOS 26, *) {
            content
                .environment(\.isOnGlass, true)
                .glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .environment(\.isOnGlass, true)
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(shape.fill((tint ?? Theme.surface).opacity(0.35)))
                        .overlay(shape.strokeBorder(Theme.specularRim, lineWidth: 1))
                }
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
    @Environment(\.isOnGlass) private var isOnGlass

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .liquidGlass(in: shape, tint: isOnGlass ? nil : tier == .surface ? Theme.surface.opacity(0.6) : Theme.elevated.opacity(0.6))
            .overlay {
                // The frosted fallback already draws its own rim.
                if #available(iOS 26, *), !isOnGlass {
                    shape.strokeBorder(Theme.specularRim, lineWidth: 0.75).allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(tier == .floating && !isOnGlass ? 0.12 : 0), radius: 16, y: 8)
    }
}

// MARK: - Buttons

/// The primary call to action: the blue-to-slate brand gradient, with a silver shine sweeping across once when it appears.
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
            // Small buttons still get a 44 pt touch target.
            .contentShape(Circle().inset(by: -max(0, (44 - size) / 2)))
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
                .typography(.titleMedium)
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

/// A soft band of light that glides across a surface once. A looping shine would keep pulling the eye. Hidden with Reduce Motion.
struct ShimmerSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        if !reduceMotion {
            GeometryReader { geometry in
                let band = geometry.size.width * 0.35
                LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: band)
                    .rotationEffect(.degrees(18))
                    .offset(x: -band + (geometry.size.width + band * 2) * progress)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).delay(0.4)) { progress = 1 }
            }
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

extension View {
    /// Floats the screen's title and Settings button over the content, which scrolls underneath.
    func screenHeader(_ title: String) -> some View {
        modifier(ScreenHeaderBar(title: title))
    }

    /// Legible text over media: a dark gradient rising from the bottom edge, as in Photos.
    func mediaCaption() -> some View {
        modifier(MediaCaption())
    }
}

private struct MediaCaption: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.top, 40)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(contrast == .increased ? 0.9 : 0.7)], startPoint: .top, endPoint: .bottom))
    }
}

private struct ScreenHeaderBar: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // A safe area bar gets the system's soft scroll edge effect.
            content.safeAreaBar(edge: .top) { ScreenHeader(title: title) }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                ScreenHeader(title: title)
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .mask(LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                            .ignoresSafeArea(edges: .top)
                    }
            }
        }
    }
}

private struct ScreenHeader: View {
    let title: String
    @Environment(\.showSettings) private var showSettings

    var body: some View {
        // Equal side columns keep the logo centred and stop the title from running into it.
        HStack(spacing: 8) {
            Text(title)
                .typography(.titleMedium)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 30)
                .accessibilityLabel("Glitter Live")
            Button(action: showSettings.callAsFunction) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(CircleIconButtonStyle())
            .accessibilityLabel("Settings")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

struct SettingsAction {
    var action: @MainActor () -> Void = {}
    @MainActor func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var showSettings = SettingsAction()
}

// MARK: - Transitions

extension View {
    /// Marks the view a sheet grows out of and shrinks back into, on iOS 18+.
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID, cornerRadius: CGFloat) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
        }
    }

    /// Presents this sheet content by zooming from its `zoomSource`, on iOS 18+.
    @ViewBuilder
    func zoomTransition(from id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

extension AnyTransition {
    /// Swapping whole screens in place: the same fade and settle in both directions, or a plain fade with Reduce Motion.
    static func screen(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
    }
}

// MARK: - Icons

extension View {
    /// An SF Symbol, and optionally its square frame, that grow with Dynamic Type like the text beside it.
    func scaledIcon(size: CGFloat, weight: Font.Weight = .regular, frame: CGFloat? = nil, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledIcon(size: size, weight: weight, frame: frame, style: style))
    }
}

private struct ScaledIcon: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let frame: CGFloat?
    @ScaledMetric private var scale: CGFloat

    init(size: CGFloat, weight: Font.Weight, frame: CGFloat?, style: Font.TextStyle) {
        self.size = size
        self.weight = weight
        self.frame = frame
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: style)
    }

    func body(content: Content) -> some View {
        // Capped so icons at the largest sizes don't crowd out the text they sit beside.
        let factor = min(scale, 2)
        content
            .font(.system(size: size * factor, weight: weight))
            .frame(width: frame.map { $0 * factor }, height: frame.map { $0 * factor })
    }
}
