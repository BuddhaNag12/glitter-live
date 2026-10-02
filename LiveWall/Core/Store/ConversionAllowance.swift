import Foundation
import Observation

/// What saving the next converted video costs: the first few are free, then a short ad each, unless Convert is unlocked.
/// Counted on the device, which is enough here because converting runs on the phone and costs nothing to serve.
@Observable
final class ConversionAllowance {
    static let freeConversions = 5

    enum Access: Equatable {
        /// Limits are off: no counts, no ads.
        case unlimited
        case free(remaining: Int)
        case ad
        case unlocked
    }

    private static let freeUsedKey = "conversion.freeUsed"

    /// Set by `Purchases` from the App Store's record of the one-time unlock.
    var isUnlocked = false
    private(set) var freeUsed: Int
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let enforcesLimits: Bool

    init(defaults: UserDefaults = .standard, enforcesLimits: Bool = FeatureFlags.conversionLimits) {
        self.defaults = defaults
        self.enforcesLimits = enforcesLimits
        freeUsed = defaults.integer(forKey: Self.freeUsedKey)
    }

    var access: Access {
        guard enforcesLimits else { return .unlimited }
        if isUnlocked { return .unlocked }
        return freeUsed < Self.freeConversions ? .free(remaining: Self.freeConversions - freeUsed) : .ad
    }

    /// Called once a video has converted, so a failed attempt costs nothing. Videos paid for with an ad don't come here.
    func recordFreeConversion() {
        guard case .free = access else { return }
        freeUsed += 1
        defaults.set(freeUsed, forKey: Self.freeUsedKey)
    }

    #if DEBUG
    func reset() {
        freeUsed = 0
        defaults.removeObject(forKey: Self.freeUsedKey)
    }
    #endif
}
