enum AppTab: String, CaseIterable, Identifiable {
    case explore, create, convert, library

    var id: Self { self }

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
