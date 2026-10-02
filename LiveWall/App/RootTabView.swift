import SwiftData
import SwiftUI

struct RootTabView: View {
    /// Explore and the first onboarding page hold their entrance animations until the launch intro has gone.
    var isLaunchIntroPlaying = false

    @State private var selection: AppTab = Self.initialTab
    @State private var showsSettings = false
    @State private var showsIntroAfterSettings = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(IncomingVideo.self) private var incoming
    @Environment(Purchases.self) private var purchases
    @AppStorage(OnboardingState.completedKey) private var hasCompletedOnboarding = false

    private static var initialTab: AppTab {
        #if DEBUG
        if let tab = DemoLaunch.initialTab.flatMap(AppTab.init(rawValue:)), AppTab.visible.contains(tab) { return tab }
        #endif
        return .explore
    }

    var body: some View {
        // The system tab bar is Apple's floating Liquid Glass bar on iOS 26+.
        TabView(selection: $selection) {
            ForEach(AppTab.visible) { tab in
                screen(for: tab)
                    // Convert always has a moving preview on screen.
                    .background { AppBackground(twinkles: tab != .convert) }
                    .environment(\.isTabSelected, selection == tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .tint(Theme.accent)
        .modifier(MinimizingTabBar())
        .task { CreationLibrary(context: modelContext).removeOrphanedFiles() }
        // A video shared from another app opens in Convert the next time the app comes forward.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active, incoming.checkInbox() { selection = .convert }
        }
        .environment(\.showSettings, SettingsAction { showsSettings = true })
        // The intro is a full-screen cover, which can only appear once the Settings sheet has gone.
        .sheet(isPresented: $showsSettings, onDismiss: showIntroIfRequested) {
            SettingsView { showsIntroAfterSettings = true }
        }
        // A layer under the launch intro rather than a full-screen cover, which could only slide up once the
        // intro had gone and showed the tabs for a moment first. The intro now fades straight into it.
        .unlockCelebration(count: purchases.unlockCount)
        .accessibilityHidden(!hasCompletedOnboarding)
        .overlay {
            if !hasCompletedOnboarding {
                OnboardingView(holdsReveal: isLaunchIntroPlaying) {
                    withAnimation(.easeOut(duration: 0.35)) { hasCompletedOnboarding = true }
                }
                .transition(.opacity)
            }
        }
    }

    private func showIntroIfRequested() {
        guard showsIntroAfterSettings else { return }
        showsIntroAfterSettings = false
        withAnimation(.easeOut(duration: 0.35)) { hasCompletedOnboarding = false }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .explore: ExploreView(holdsReveal: isLaunchIntroPlaying || !hasCompletedOnboarding)
        case .create: CreateView()
        case .convert: ConvertView()
        case .library: LibraryView { selection = .convert }
        }
    }
}

/// Shrinks the tab bar while scrolling down, like Photos and Music.
private struct MinimizingTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}
