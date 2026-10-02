import SwiftUI

extension View {
    /// Sparkles burst from the center and a badge pops in each time `count` goes up, with a success haptic.
    func unlockCelebration(count: Int) -> some View {
        modifier(UnlockCelebration(count: count))
    }
}

private struct UnlockCelebration: ViewModifier {
    let count: Int
    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isShowing {
                    CelebrationBurst()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .sensoryFeedback(.success, trigger: count)
            .onChange(of: count) {
                withAnimation(.easeOut(duration: 0.2)) { isShowing = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.easeOut(duration: 0.35)) { isShowing = false }
                }
            }
    }
}

private struct CelebrationBurst: View {
    @State private var progress: CGFloat = 0
    @State private var badgeIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sparkCount = 16

    var body: some View {
        ZStack {
            // Dims what's behind, so the glass badge reads cleanly over busy screens.
            Color.black.opacity(0.3).ignoresSafeArea()
            if !reduceMotion {
                ForEach(0..<Self.sparkCount, id: \.self) { index in
                    let angle = Angle.degrees(Double(index) / Double(Self.sparkCount) * 360 + (index.isMultiple(of: 2) ? 8 : -8))
                    let distance = (index.isMultiple(of: 3) ? 200 : 155) * progress
                    Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "star.fill")
                        .font(.system(size: index.isMultiple(of: 3) ? 26 : 18, weight: .bold))
                        .foregroundStyle(index.isMultiple(of: 2) ? Theme.accent : Theme.signalYellow)
                        .offset(x: cos(angle.radians) * distance, y: sin(angle.radians) * distance)
                        .scaleEffect(0.4 + progress * 0.8)
                        .opacity(1 - Double(progress) * 0.6)
                }
            }
            VStack(spacing: 10) {
                Image(systemName: "infinity")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 76, height: 76)
                    .background(Theme.accentGradient, in: Circle())
                Text("Unlimited unlocked")
                    .typography(.titleMedium)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(24)
            // Solid underneath, so rows behind don't show through the glass.
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .glass(.floating, cornerRadius: 30)
            .scaleEffect(badgeIn || reduceMotion ? 1 : 0.6)
            .opacity(badgeIn ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unlimited conversions unlocked")
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.45)) { badgeIn = true }
            withAnimation(.easeOut(duration: 1.5)) { progress = 1 }
        }
    }
}
