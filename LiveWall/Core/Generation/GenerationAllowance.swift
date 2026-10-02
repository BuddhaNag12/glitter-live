import Foundation
import Observation

/// What the next generation costs the user. Counted on the device for now; the server becomes the source
/// of truth once it exists, since anything stored here resets with a reinstall.
@Observable
final class GenerationAllowance {
    static let freeGenerations = 5
    static let dailyAdGenerations = 10
    static let monthlyProGenerations = 100

    enum Access: Equatable {
        /// Limits are off for testing: no counts, no ads.
        case unlimited
        case free(remaining: Int)
        case ad(remainingToday: Int)
        case pro(remainingThisMonth: Int)
        case dailyLimitReached
        case monthlyLimitReached
    }

    private enum Key {
        static let freeUsed = "generation.freeUsed"
        static let adDay = "generation.adDay"
        static let adUsed = "generation.adUsed"
        static let proMonth = "generation.proMonth"
        static let proUsed = "generation.proUsed"
    }

    var isPro = false
    private(set) var freeUsed: Int
    private var adDay: String
    private var adUsed: Int
    private var proMonth: String
    private var proUsed: Int
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let enforcesLimits: Bool

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init, enforcesLimits: Bool = FeatureFlags.generationLimits) {
        self.defaults = defaults
        self.now = now
        self.enforcesLimits = enforcesLimits
        freeUsed = defaults.integer(forKey: Key.freeUsed)
        adDay = defaults.string(forKey: Key.adDay) ?? ""
        adUsed = defaults.integer(forKey: Key.adUsed)
        proMonth = defaults.string(forKey: Key.proMonth) ?? ""
        proUsed = defaults.integer(forKey: Key.proUsed)
    }

    var access: Access {
        guard enforcesLimits else { return .unlimited }
        if isPro {
            let used = proMonth == month ? proUsed : 0
            return used < Self.monthlyProGenerations ? .pro(remainingThisMonth: Self.monthlyProGenerations - used) : .monthlyLimitReached
        }
        if freeUsed < Self.freeGenerations { return .free(remaining: Self.freeGenerations - freeUsed) }
        let used = adDay == day ? adUsed : 0
        return used < Self.dailyAdGenerations ? .ad(remainingToday: Self.dailyAdGenerations - used) : .dailyLimitReached
    }

    /// Called once a generation has succeeded, so a failed one costs nothing.
    func recordGeneration() {
        switch access {
        case .free:
            freeUsed += 1
            defaults.set(freeUsed, forKey: Key.freeUsed)
        case .ad:
            adUsed = adDay == day ? adUsed + 1 : 1
            adDay = day
            defaults.set(adUsed, forKey: Key.adUsed)
            defaults.set(adDay, forKey: Key.adDay)
        case .pro:
            proUsed = proMonth == month ? proUsed + 1 : 1
            proMonth = month
            defaults.set(proUsed, forKey: Key.proUsed)
            defaults.set(proMonth, forKey: Key.proMonth)
        case .unlimited, .dailyLimitReached, .monthlyLimitReached:
            break
        }
    }

    /// In the user's own time zone, so the daily limit resets at their midnight.
    private var day: String {
        let date = Calendar.current.dateComponents([.year, .month, .day], from: now())
        return "\(date.year ?? 0)-\(date.month ?? 0)-\(date.day ?? 0)"
    }

    private var month: String {
        let date = Calendar.current.dateComponents([.year, .month], from: now())
        return "\(date.year ?? 0)-\(date.month ?? 0)"
    }
}

/// Plays a rewarded ad and reports whether it was watched to the end.
protocol RewardedAdPresenter {
    func present() async -> Bool
}
