import Foundation

/// Features that exist in code but aren't ready to ship.
enum FeatureFlags {
    /// The Create tab and every mention of AI generation. Shipped from 1.1: the server enforces the ad and the
    /// daily limits (`supabase/functions/generate`), so the app no longer has to keep it hidden.
    static let aiGeneration = true

    /// AI video for the motion (LTX on fal). Off until the fal account has credit: the image is still made by AI,
    /// and the phone animates it with depth parallax, which costs nothing.
    static let aiMotion = false

    /// The ad and Pro limits on Create: an ad before each generation, 3 a day. On in debug too, so the ad flow gets tested.
    static let generationLimits = true

    /// Convert's 5 free conversions, then an ad or the one-time unlock.
    static let conversionLimits = true

    /// Whether anything can ask for a rewarded ad, so ads and their consent prompts stay out of builds that don't use them.
    static var showsAds: Bool { conversionLimits || (aiGeneration && generationLimits) }
}
