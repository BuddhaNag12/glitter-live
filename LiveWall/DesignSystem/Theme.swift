import SwiftUI

/// "Silver Shimmer" design tokens: an obsidian dark mode lit by brand blue and silver slate, and a
/// soft slate light mode. Every color adapts to light and dark mode, and text, borders and accents
/// get stronger values when Increase Contrast is on.
enum Theme {
    static let background = Color(light: 0xF8FAFC, dark: 0x090C12)
    static let surface = Color(light: 0xFFFFFF, dark: 0x121722)
    static let elevated = Color(light: 0xF1F5F9, dark: 0x1A202B)
    static let border = Color(light: 0xE2E8F0, dark: 0xFFFFFF, darkOpacity: 0.10,
                              increased: .init(light: 0x64748B, dark: 0xFFFFFF, darkOpacity: 0.45))
    /// Controls and rows sitting on a glass panel.
    static let fill = Color(light: 0x0F172A, lightOpacity: 0.05, dark: 0xFFFFFF, darkOpacity: 0.07,
                            increased: .init(light: 0x0F172A, lightOpacity: 0.10, dark: 0xFFFFFF, darkOpacity: 0.14))

    /// Background light leaks: brand blue top-left, silver slate bottom-right.
    static let glowPrimary = Color(light: 0x3B82F6, lightOpacity: 0.10, dark: 0x3B82F6, darkOpacity: 0.40)
    static let glowSecondary = Color(light: 0x64748B, lightOpacity: 0.10, dark: 0x94A3B8, darkOpacity: 0.30)

    /// Brand blue for text, icons and selection. Lighter in dark mode so small text keeps 4.5:1 contrast.
    static let accent = Color(light: 0x2563EB, dark: 0x93C5FD, increased: .init(light: 0x1D4ED8, dark: 0xBFDBFE))
    /// Brand blue behind white text: badges, switches, selected states.
    static let accentFill = Color(light: 0x2563EB, dark: 0x3B82F6, increased: .init(light: 0x1D4ED8, dark: 0x2563EB))
    /// Blue fading into slate, like the icon's brush. Both ends keep white text at 3:1 or better for bold labels.
    static let accentGradient = LinearGradient(
        colors: [Color(light: 0x2563EB, dark: 0x3B82F6, increased: .init(light: 0x1D4ED8, dark: 0x2563EB)),
                 Color(light: 0x64748B, dark: 0x7C8BA1, increased: .init(light: 0x475569, dark: 0x64748B))],
        startPoint: .leading, endPoint: .trailing
    )
    static let onAccent = Color.white
    /// Secondary text on photos and video, such as card subtitles.
    static let onMediaSecondary = Color(light: 0xFFFFFF, lightOpacity: 0.8, dark: 0xFFFFFF, darkOpacity: 0.8,
                                        increased: .init(light: 0xFFFFFF, dark: 0xFFFFFF))
    static let slate = Color(light: 0x64748B, dark: 0x94A3B8, increased: .init(light: 0x475569, dark: 0xCBD5E1))
    static let danger = Color(light: 0xDC2626, dark: 0xF87171, increased: .init(light: 0xB91C1C, dark: 0xFCA5A5))
    /// The Live Photo indicator, as in Photos.
    static let signalYellow = Color(light: 0xCA8A04, dark: 0xFACC15, increased: .init(light: 0xA16207, dark: 0xFDE047))
    /// Trim handles sit on the filmstrip, so they stay bright in both modes.
    static let trimHandle = Color(hex: 0xFACC15)

    static let textPrimary = Color(light: 0x0F172A, dark: 0xF8FAFC)
    static let textSecondary = Color(light: 0x475569, dark: 0xA1A9B8, increased: .init(light: 0x334155, dark: 0xCBD5E1))
    static let textTertiary = Color(light: 0x64748B, dark: 0x7C8698, increased: .init(light: 0x475569, dark: 0xA1A9B8))

    static let stroke = border
    static let specularRim = LinearGradient(
        colors: [Color(light: 0x0F172A, lightOpacity: 0.08, dark: 0xFFFFFF, darkOpacity: 0.16,
                       increased: .init(light: 0x0F172A, lightOpacity: 0.30, dark: 0xFFFFFF, darkOpacity: 0.45)),
                 Color(light: 0x0F172A, lightOpacity: 0.04, dark: 0xFFFFFF, darkOpacity: 0.05,
                       increased: .init(light: 0x0F172A, lightOpacity: 0.30, dark: 0xFFFFFF, darkOpacity: 0.45))],
        startPoint: .top, endPoint: .bottom
    )

    /// Wallpaper previews always sit on a dark Lock Screen, whatever the app's appearance.
    static let lockScreen = Color(hex: 0x0F172A)
}

/// Colors for placeholder wallpaper art. Fixed, because they stand in for real wallpapers.
enum WallpaperPalette {
    static let blue = Color(hex: 0x3B82F6)
    static let indigo = Color(hex: 0x6366F1)
    static let sky = Color(hex: 0x0EA5E9)
    static let violet = Color(hex: 0x8B5CF6)
    static let rose = Color(hex: 0xF43F5E)
    static let amber = Color(hex: 0xF59E0B)
    static let teal = Color(hex: 0x14B8A6)
    static let `default` = [blue, indigo, sky]
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(light: UInt32, lightOpacity: Double = 1, dark: UInt32, darkOpacity: Double = 1, increased: ContrastVariant? = nil) {
        let standard = ContrastVariant(light: light, lightOpacity: lightOpacity, dark: dark, darkOpacity: darkOpacity)
        // SwiftUI can resolve colors on its render thread, so the provider mustn't inherit main-actor isolation.
        self.init(uiColor: UIColor { @Sendable traits in
            let variant = traits.accessibilityContrast == .high ? increased ?? standard : standard
            return traits.userInterfaceStyle == .dark
                ? UIColor(hex: variant.dark, alpha: variant.darkOpacity)
                : UIColor(hex: variant.light, alpha: variant.lightOpacity)
        })
    }
}

/// A color's light and dark values, used for its Increase Contrast version.
nonisolated struct ContrastVariant: Sendable {
    var light: UInt32
    var lightOpacity: Double = 1
    var dark: UInt32
    var darkOpacity: Double = 1
}

extension UIColor {
    nonisolated convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

enum InterWeight: String {
    case light = "Inter-Light"
    case regular = "Inter-Regular"
    case medium = "Inter-Medium"
    case semibold = "Inter-SemiBold"
    case bold = "Inter-Bold"
}

extension Font {
    static func inter(_ size: CGFloat, _ weight: InterWeight = .regular, relativeTo style: TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    static let displayLarge = Typography.displayLarge.font
    static let headlineLarge = Typography.headlineLarge.font
    static let headlineSmall = Typography.headlineSmall.font
    static let titleMedium = Typography.titleMedium.font
    static let bodyLarge = Typography.bodyLarge.font
    static let bodyMedium = Typography.bodyMedium.font
    static let labelLarge = Typography.labelLarge.font
    static let labelMedium = Typography.labelMedium.font
    static let labelSmall = Typography.labelSmall.font
}

/// A text style's font together with the tracking its size needs, which a `Font` can't carry.
struct Typography {
    let size: CGFloat
    let font: Font

    init(_ size: CGFloat, _ weight: InterWeight, relativeTo style: Font.TextStyle) {
        self.size = size
        font = .inter(size, weight, relativeTo: style)
    }

    /// Inter's dynamic metrics: tighter as text grows, slightly open when small (rsms.me/inter/dynmetrics).
    var tracking: CGFloat { size * (-0.0223 + 0.185 * exp(-0.1745 * size)) }

    static let displayLarge = Typography(32, .bold, relativeTo: .largeTitle)
    static let headlineLarge = Typography(28, .semibold, relativeTo: .title)
    static let headlineSmall = Typography(20, .semibold, relativeTo: .title3)
    static let titleMedium = Typography(17, .semibold, relativeTo: .headline)
    static let bodyLarge = Typography(17, .regular, relativeTo: .body)
    static let bodyMedium = Typography(15, .regular, relativeTo: .subheadline)
    /// Labels inside compact controls, where 17 pt titles don't fit beside a value.
    static let labelLarge = Typography(15, .semibold, relativeTo: .subheadline)
    static let labelMedium = Typography(13, .medium, relativeTo: .footnote)
    static let labelSmall = Typography(11, .semibold, relativeTo: .caption)
}

extension View {
    /// Sets a text style's font and its size-specific tracking. Uppercase labels keep their own wider tracking via `.font`.
    func typography(_ style: Typography) -> some View {
        font(style.font).tracking(style.tracking)
    }
}

/// Obsidian base with two soft glows and a slow glitter twinkle, shared by every screen.
struct AppBackground: View {
    /// Screens with their own motion, such as a playing wallpaper, hold the glitter still so it doesn't compete.
    var twinkles = true

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.glowPrimary, .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.glowSecondary, .clear], center: .bottomTrailing, startRadius: 0, endRadius: 560)
            GlitterField(isAnimated: twinkles)
        }
        .ignoresSafeArea()
    }
}
