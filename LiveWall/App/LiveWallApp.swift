import SwiftData
import SwiftUI

@main
struct LiveWallApp: App {
    private let modelContainer = Self.makeModelContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
                .tint(Theme.cyan)
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
