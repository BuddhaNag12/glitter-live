import SwiftUI

struct RootTabView: View {
    @State private var selection: AppTab = Self.initialTab
    @State private var showsSettings = false
    @AppStorage(OnboardingState.completedKey) private var hasCompletedOnboarding = false

    private static var initialTab: AppTab {
        #if DEBUG
        if let tab = DemoLaunch.initialTab.flatMap(AppTab.init(rawValue:)) { return tab }
        #endif
        return .convert
    }

    var body: some View {
        // The system tab bar is Apple's floating Liquid Glass bar on iOS 26+.
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                screen(for: tab)
                    .background { AppBackground() }
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .tint(Theme.cyan)
        .modifier(MinimizingTabBar())
        .sensoryFeedback(.selection, trigger: selection)
        .environment(\.showSettings, SettingsAction { showsSettings = true })
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: Binding(get: { !hasCompletedOnboarding }, set: { hasCompletedOnboarding = !$0 })) {
            OnboardingView { hasCompletedOnboarding = true }
                .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .explore: ExploreComingSoonView()
        case .create: CreateComingSoonView()
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
