/// Features that exist in code but aren't ready to ship.
enum FeatureFlags {
    /// The Create tab and every mention of AI generation. On only in debug builds until generation works end to end,
    /// because App Review rejects placeholder screens and advertising features that aren't available.
    #if DEBUG
    static let aiGeneration = true
    #else
    static let aiGeneration = false
    #endif
}
