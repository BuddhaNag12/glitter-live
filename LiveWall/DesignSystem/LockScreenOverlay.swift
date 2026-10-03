import SwiftUI

/// Mimics the iOS Lock Screen chrome so users can frame the wallpaper around the clock and widgets.
struct LockScreenOverlay: View {
    var showsMotionBadge = false

    /// The time shown on the mock clock. `-lockScreenTime 9:41` pins it for App Store screenshots and previews,
    /// so it matches the simulator's overridden status bar. It's a launch argument, so it works in release builds too.
    private var shownDate: Date {
        guard let pinned = UserDefaults.standard.string(forKey: "lockScreenTime"),
              let colon = pinned.firstIndex(of: ":"),
              let hour = Int(pinned[..<colon]), let minute = Int(pinned[pinned.index(after: colon)...])
        else { return .now }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 393
            VStack(spacing: 0) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18 * scale, weight: .semibold))
                    .padding(.bottom, 8 * scale)
                Text(shownDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.custom(InterWeight.medium.rawValue, fixedSize: 21 * scale))
                Text(shownDate, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.custom(InterWeight.light.rawValue, fixedSize: 100 * scale))
                    .tracking(-2 * scale)
                    .monospacedDigit()
                    .padding(.top, -6 * scale)
                widgets(scale: scale)
                    .padding(.top, 6 * scale)
                Spacer()
                if showsMotionBadge {
                    Label("Lock Screen motion ready", systemImage: "bolt.fill")
                        .font(.custom(InterWeight.semibold.rawValue, fixedSize: 14 * scale))
                        .padding(.horizontal, 14 * scale)
                        .frame(height: 32 * scale)
                        .background(.black.opacity(0.35), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                        .padding(.bottom, 14 * scale)
                }
                HStack {
                    quickAction("flashlight.off.fill", scale: scale)
                    Spacer()
                    quickAction("camera.fill", scale: scale)
                }
                .padding(.horizontal, 44 * scale)
                .padding(.bottom, 34 * scale)
            }
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.35), radius: 6)
            .frame(maxWidth: .infinity)
            .padding(.top, geometry.size.height * 0.075)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func widgets(scale: CGFloat) -> some View {
        HStack(spacing: 14 * scale) {
            Label("82%", systemImage: "battery.75percent")
            Label("24°", systemImage: "sun.max.fill")
            Label("6,240", systemImage: "figure.walk")
        }
        .font(.custom(InterWeight.semibold.rawValue, fixedSize: 15 * scale))
        .labelStyle(WidgetLabelStyle(spacing: 4 * scale))
        .padding(.horizontal, 16 * scale)
        .frame(height: 38 * scale)
        .background(.white.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }

    private func quickAction(_ symbol: String, scale: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20 * scale))
            .frame(width: 50 * scale, height: 50 * scale)
            .background(.black.opacity(0.35), in: Circle())
            .opacity(0.85)
    }
}

private struct WidgetLabelStyle: LabelStyle {
    var spacing: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

/// Rounded phone bezel that frames lock-screen previews.
struct DeviceFrame<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            let bezel = geometry.size.width * 0.03
            let outerRadius = geometry.size.width * 0.14
            let outer = RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
            content
                .clipShape(RoundedRectangle(cornerRadius: outerRadius - bezel, style: .continuous))
                .padding(bezel)
                .background(Color(hex: 0x16171D), in: outer)
                .overlay(outer.strokeBorder(highlighted ? AnyShapeStyle(Theme.accentFill) : AnyShapeStyle(Color.white.opacity(0.12)), lineWidth: highlighted ? 2 : 1.5))
                .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
        }
        .aspectRatio(WallpaperFormat.aspectRatio, contentMode: .fit)
        // A Lock Screen is dark whatever the app's appearance, and so are the controls drawn on it.
        .environment(\.colorScheme, .dark)
    }
}
