import SwiftUI

/// Slowly drifting neon light, used for hero art where there is no real wallpaper to show.
struct AuroraView: View {
    var colors: [Color] = [Theme.cyan, Theme.violet, Theme.magenta]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The drift is slow, so 20 fps looks the same as 120 at a fraction of the GPU cost.
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / 6
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    Theme.base
                    ForEach(colors.indices, id: \.self) { index in
                        let phase = Double(index) * 2.1
                        Circle()
                            .fill(colors[index].opacity(0.85))
                            .frame(width: size.width * 0.9, height: size.width * 0.9)
                            .position(
                                x: size.width * (0.5 + 0.3 * cos(t + phase)),
                                y: size.height * (0.5 + 0.28 * sin(t * 1.3 + phase))
                            )
                    }
                }
                .blur(radius: size.width * 0.18)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
