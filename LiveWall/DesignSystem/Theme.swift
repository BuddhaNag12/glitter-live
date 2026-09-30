import SwiftUI

/// Design tokens for the "Obsidian Kinetic" look.
enum Theme {
    static let base = Color(hex: 0x0A0A0E)
    static let surface = Color(hex: 0x12131A)
    static let card = Color(hex: 0x1A1B24)

    static let cyan = Color(hex: 0x00F0FF)
    static let violet = Color(hex: 0x8A2BE2)
    static let magenta = Color(hex: 0xFF007F)
    static let lavender = Color(hex: 0xB4A6FF)
    static let signalYellow = Color(hex: 0xFFE600)
    static let gold = Color(hex: 0xFFD700)

    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.64)
    static let textTertiary = Color.white.opacity(0.42)

    static let stroke = Color.white.opacity(0.08)
    static let strokeHighlight = Color.white.opacity(0.16)

    static let kinetic = LinearGradient(colors: [cyan, violet, magenta], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let action = LinearGradient(colors: [Color(hex: 0x3EEAF6), lavender], startPoint: .leading, endPoint: .trailing)
    static let vip = LinearGradient(colors: [gold, magenta, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let specularRim = LinearGradient(colors: [strokeHighlight, stroke], startPoint: .top, endPoint: .bottom)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
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

    static let displayLarge = inter(32, .bold, relativeTo: .largeTitle)
    static let headlineLarge = inter(28, .semibold, relativeTo: .title)
    static let headlineSmall = inter(20, .semibold, relativeTo: .title3)
    static let titleMedium = inter(17, .semibold, relativeTo: .headline)
    static let bodyLarge = inter(17, .regular, relativeTo: .body)
    static let bodyMedium = inter(15, .regular, relativeTo: .subheadline)
    static let labelMedium = inter(13, .medium, relativeTo: .footnote)
    static let labelSmall = inter(11, .semibold, relativeTo: .caption)
}

/// Background shared by every screen: obsidian base with faint cyan and violet light leaks.
struct AppBackground: View {
    var body: some View {
        Theme.base
            .overlay(alignment: .topLeading) {
                RadialGradient(colors: [Theme.cyan.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 420)
            }
            .overlay(alignment: .bottomTrailing) {
                RadialGradient(colors: [Theme.violet.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 480)
            }
            .ignoresSafeArea()
    }
}
