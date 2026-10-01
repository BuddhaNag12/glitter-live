import Foundation

/// A look for the generated wallpaper, added to what the user typed.
nonisolated enum WallpaperStyle: String, CaseIterable, Identifiable, Sendable {
    case cinematic, anime, liquid, nature, neon, cosmic

    var id: Self { self }

    var title: String {
        switch self {
        case .cinematic: "Cinematic"
        case .anime: "Anime"
        case .liquid: "Liquid"
        case .nature: "Nature"
        case .neon: "Neon"
        case .cosmic: "Cosmic"
        }
    }

    var symbol: String {
        switch self {
        case .cinematic: "film"
        case .anime: "sparkles"
        case .liquid: "drop"
        case .nature: "leaf"
        case .neon: "bolt"
        case .cosmic: "moon.stars"
        }
    }

    var promptSuffix: String {
        switch self {
        case .cinematic: "cinematic lighting, shallow depth of field, photorealistic"
        case .anime: "anime illustration, vibrant colors, soft glow"
        case .liquid: "glossy liquid chrome, flowing abstract shapes"
        case .nature: "serene landscape, natural light, highly detailed"
        case .neon: "neon lights, synthwave, glowing on a dark background"
        case .cosmic: "deep space, nebula, glittering stars, ethereal"
        }
    }

    /// Colors for the stand-in generator and the style's swatch.
    var palette: [UInt32] {
        switch self {
        case .cinematic: [0xF59E0B, 0x7C2D12, 0x1E3A8A]
        case .anime: [0xF472B6, 0x818CF8, 0x22D3EE]
        case .liquid: [0x94A3B8, 0x38BDF8, 0x6366F1]
        case .nature: [0x22C55E, 0x0EA5E9, 0xFACC15]
        case .neon: [0xEC4899, 0x8B5CF6, 0x06B6D4]
        case .cosmic: [0x6366F1, 0xA855F7, 0x0EA5E9]
        }
    }
}

nonisolated struct GenerationRequest: Sendable, Equatable {
    static let maximumPromptLength = 280

    var prompt: String
    var style: WallpaperStyle

    var fullPrompt: String {
        "\(prompt.trimmingCharacters(in: .whitespacesAndNewlines)), \(style.promptSuffix), vertical phone wallpaper, no text"
    }
}

/// Makes a wallpaper image, then animates it. Separate steps, so the image can show while its motion is made.
nonisolated protocol GenerationService: Sendable {
    /// A 9:16 still, as a local file.
    func makeImage(for request: GenerationRequest) async throws -> URL
    /// A clip of about 3 seconds that starts on the image, as a local file.
    func animate(imageAt url: URL, for request: GenerationRequest) async throws -> URL
}

nonisolated enum GenerationError: LocalizedError {
    case imageFailed
    case videoFailed

    var errorDescription: String? {
        switch self {
        case .imageFailed: "The wallpaper image couldn't be made. Try again in a moment."
        case .videoFailed: "The wallpaper couldn't be brought to life. Try again in a moment."
        }
    }
}

nonisolated enum SurprisePrompts {
    static let all = [
        "Bioluminescent koi gliding through liquid starlight",
        "A lone lighthouse under swirling northern lights",
        "Cherry blossoms drifting over a quiet Kyoto street at dusk",
        "Molten gold waves folding in slow motion",
        "A glass jellyfish floating through a violet nebula",
        "Rain on a neon Tokyo alley, reflections shimmering",
        "Snow falling over a misty pine forest at blue hour",
        "An ocean of clouds below a mountain summit at sunrise",
    ]
}
