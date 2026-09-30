enum AppTab: String, CaseIterable, Identifiable {
    case explore, create, convert, library

    var id: Self { self }

    static var visible: [AppTab] {
        allCases.filter { $0 != .create || FeatureFlags.aiGeneration }
    }

    var title: String {
        switch self {
        case .explore: "Explore"
        case .create: "Create"
        case .convert: "Convert"
        case .library: "Library"
        }
    }

    var symbol: String {
        switch self {
        case .explore: "sparkles"
        case .create: "wand.and.stars"
        case .convert: "livephoto"
        case .library: "photo.on.rectangle.angled"
        }
    }
}
