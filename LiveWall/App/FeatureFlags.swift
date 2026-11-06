import Foundation

/// Features that exist in code but aren't ready to ship.
enum FeatureFlags {
    /// The Create tab and every mention of AI generation. On only in debug builds until generation works end to end,
    /// because App Review rejects placeholder screens and advertising features that aren't available.
    #if DEBUG
    /// `-releaseFeatures` hides it in debug too, so App Store screenshots match what ships.
    static let aiGeneration = !ProcessInfo.processInfo.arguments.contains("-releaseFeatures")
    #elseif AI_BETA
    /// Internal TestFlight builds from the "AI beta" Xcode Cloud workflow; App Store builds never set AI_BETA.
    static let aiGeneration = true
    #else
    static let aiGeneration = false
    #endif

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
