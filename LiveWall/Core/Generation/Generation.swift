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
        // Image models don't understand negatives, so "no text" would only invite text.
        "\(prompt.trimmingCharacters(in: .whitespacesAndNewlines)), \(style.promptSuffix), vertical phone wallpaper"
    }
}

/// Brings a still to life as a clip of about 3 seconds that starts on the image, as a local file.
nonisolated protocol WallpaperAnimator: Sendable {
    func animate(imageAt url: URL, for request: GenerationRequest) async throws -> URL
}

/// Makes a wallpaper image, then animates it. Separate steps, so the image can show while its motion is made.
nonisolated protocol GenerationService: WallpaperAnimator {
    /// The wallpaper still, as a local file. It may be square; the clip is cropped to 9:16.
    func makeImage(for request: GenerationRequest) async throws -> URL
}

nonisolated enum GenerationError: LocalizedError {
    case imageFailed
    case videoFailed
    /// The server's own explanation, such as a prompt it won't generate.
    case server(String?)

    var errorDescription: String? {
        switch self {
        case .imageFailed: "The wallpaper image couldn't be made. Try again in a moment."
        case .videoFailed: "The wallpaper couldn't be brought to life. Try again in a moment."
        case .server(let message): message ?? "Generation is unavailable right now. Try again in a moment."
        }
    }
}

nonisolated enum SurprisePrompts {
    /// Each centers one clear subject in front of a distinct background, which crops well to 9:16 and gives the depth motion layers to move.
    static let all = [
        "Bioluminescent koi gliding through liquid starlight",
        "A lone lighthouse under swirling northern lights",
        "Cherry blossoms drifting over a quiet Kyoto street at dusk",
        "Molten gold waves folding in slow motion",
        "A glass jellyfish floating through a violet nebula",
        "Rain on a neon Tokyo alley, reflections shimmering",
        "Snow falling over a misty pine forest at blue hour",
        "An ocean of clouds below a mountain summit at sunrise",
        "A red fox curled up in fresh snow under falling flakes",
        "A tiny cabin with warm lit windows in a snowy forest at night",
        "A samurai on a cliff edge beneath a giant red moon",
        "A hot air balloon rising over misty valleys at golden hour",
        "A white owl perched on a branch under a full moon",
        "A crystal-clear wave curling over a turquoise reef",
        "A lantern-lit paper boat on a calm dark lake",
        "An astronaut floating above Earth with the sunrise behind",
        "A giant whale swimming through clouds at sunset",
        "A single dandelion releasing seeds into warm evening light",
        "A desert dune at twilight under a sky full of stars",
        "A waterfall pouring into a hidden emerald pool",
        "A neon-lit vintage car parked on a rainy street",
        "A golden retriever puppy in a field of sunflowers",
        "A bonsai tree on a floating rock above the clouds",
        "A spiral galaxy glowing above a quiet mountain lake",
        "A hummingbird hovering beside a glowing pink flower",
        "A castle on a misty hill with a dragon circling above",
        "A peacock with its tail fanned out in jewel colors",
        "A city skyline reflected in still water at blue hour",
        "A wolf howling on a snowy ridge under the aurora",
        "A floating island with waterfalls spilling into the sky",
        "A butterfly made of stained glass catching the light",
        "A lone tree on a hill beneath the Milky Way",
        "A koi pond with lotus flowers and drifting petals",
        "A train crossing a stone bridge through autumn mountains",
        "A sleeping cat on a windowsill as rain falls outside",
        "A futuristic city with flying cars at sunset",
        "A deer standing in a foggy forest with sun rays",
        "A jellyfish swarm glowing in the deep blue ocean",
        "A sailboat on a golden sea under pastel clouds",
        "A glowing mushroom forest at night with fireflies",
        "A phoenix rising in flames against a dark sky",
        "A Japanese torii gate standing in a calm sea at dawn",
        "A polar bear on drifting ice under a pink sky",
        "A cup of coffee steaming beside a rainy window",
        "A sea turtle gliding over a coral reef in sunbeams",
        "A snow leopard resting on a rocky mountain ledge",
        "A field of lavender stretching toward a purple sunset",
        "A medieval village lit by lanterns on a winter night",
        "An eagle soaring over a canyon at golden hour",
        "A mermaid silhouette beneath shimmering ocean light",
        "A cozy reading nook by a frosted window on a snowy evening",
        "A robot gardener tending glowing plants in a greenhouse",
        "A fireworks burst over a calm harbor at night",
        "A lone surfer walking along a beach at sunset",
        "A tiger walking through tall grass in morning mist",
        "A crescent moon over a minaret skyline at dusk",
        "A crystal cave lit by glowing blue gems",
        "A field of tulips with a windmill under soft clouds",
        "A lion with a flowing mane in warm savanna light",
        "A rainy forest path with a red umbrella in the middle",
        "A space station orbiting a ringed planet",
        "A swan gliding across a misty lake at sunrise",
        "A rocket launching into a starry sky",
        "A lonely bench under a glowing street lamp in the fog",
        "A flamingo standing in a pink lagoon at sunset",
        "A frozen waterfall glowing blue in winter light",
        "A dragon curled around a mountain peak in the clouds",
        "A vintage motorcycle on an empty desert highway",
        "A garden of glowing roses under a starry sky",
        "A sea of lanterns floating into the night sky",
        "A panda eating bamboo in a misty bamboo forest",
        "An old ship sailing through a stormy sea with lightning",
        "A meadow of wildflowers with mountains behind at dawn",
        "A geisha with a red umbrella on a snowy bridge",
        "A planet rising over an alien desert landscape",
        "A cherry blossom tree beside a temple pond",
        "A grand piano on a beach at sunset",
        "A hedgehog in autumn leaves under soft light",
        "A gondola drifting through a Venice canal at dusk",
        "A comet streaking across a violet night sky",
        "A lighthouse beam cutting through a rolling fog",
        "A hammock between palm trees on a turquoise beach",
        "A raven perched on a lantern on a foggy night",
        "A neon jellyfish drifting through a dark rainy alley",
        "A treehouse village glowing among giant redwoods",
        "A horse running through shallow water at sunrise",
        "A glass terrarium with a tiny glowing world inside",
        "A snowy mountain cabin beneath the northern lights",
        "An octopus with glowing tentacles in the deep sea",
        "A field of fireflies over a quiet country road",
        "A golden temple on a mountain above the clouds",
        "A violin resting on sheet music in warm candlelight",
        "A blue morpho butterfly on a dewy leaf",
        "A lone astronaut on the moon watching Earth rise",
        "A steampunk airship drifting over a sunset city",
        "A cozy campfire under a blanket of stars",
        "A crystal swan sculpture glowing in soft light",
        "A waterfall of stars pouring off a cliff into space",
        "A fox spirit with glowing tails in a moonlit forest",
        "A lotus flower opening on a dark reflective pond",
    ]
}
