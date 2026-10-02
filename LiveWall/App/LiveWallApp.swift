import SwiftData
import SwiftUI

/// Lets screenshot tests pin an appearance with `-appearance light|dark`; otherwise the app follows the system.
enum DemoAppearance {
    static var override: ColorScheme? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
        #else
        return nil
        #endif
    }
}

@main
struct LiveWallApp: App {
    private let modelContainer = Self.makeModelContainer()
    @State private var playsLaunchIntro = LaunchIntro.shouldPlay
    @State private var conversions: ConversionAllowance
    @State private var purchases: Purchases

    init() {
        let conversions = ConversionAllowance()
        _conversions = State(initialValue: conversions)
        _purchases = State(initialValue: Purchases(conversions: conversions))
        // Catalog thumbnails are immutable, so a larger cache means they download once.
        URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView(isLaunchIntroPlaying: playsLaunchIntro)
                if playsLaunchIntro {
                    LaunchIntroView { playsLaunchIntro = false }
                }
            }
            .preferredColorScheme(DemoAppearance.override)
            .tint(Theme.accent)
            .environment(conversions)
            .environment(purchases)
            .task { await purchases.load() }
            .task { if FeatureFlags.showsAds { await RewardedAds.shared.warmUp() } }
        }
        .modelContainer(modelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        var inMemory = false
        #if DEBUG
        inMemory = DemoLaunch.isDemo
        #endif
        do {
            return try ModelContainer(for: Creation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
        } catch {
            // A broken store shouldn't stop people converting; the library just won't persist this launch.
            return try! ModelContainer(for: Creation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }
}
