import Foundation
import Testing
@testable import LiveWall

@MainActor
struct GenerationAllowanceTests {
    private let defaults = UserDefaults(suiteName: "GenerationAllowanceTests-\(UUID().uuidString)")!

    @Test func startsWithFiveFreeThenAsksForAnAd() {
        let allowance = GenerationAllowance(defaults: defaults, enforcesLimits: true)
        #expect(allowance.access == .free(remaining: 5))
        for _ in 0..<5 { allowance.recordGeneration() }
        #expect(allowance.access == .ad(remainingToday: 10))
    }

    @Test func stopsAdGenerationsAtTheDailyLimitUntilTomorrow() {
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        let allowance = GenerationAllowance(defaults: defaults, now: { now }, enforcesLimits: true)
        for _ in 0..<15 { allowance.recordGeneration() }
        #expect(allowance.access == .dailyLimitReached)

        now.addTimeInterval(24 * 60 * 60)
        #expect(allowance.access == .ad(remainingToday: 10))
    }

    @Test func proSkipsAdsAndRefillsMonthly() {
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        let allowance = GenerationAllowance(defaults: defaults, now: { now }, enforcesLimits: true)
        allowance.isPro = true
        for _ in 0..<100 { allowance.recordGeneration() }
        #expect(allowance.access == .monthlyLimitReached)

        now.addTimeInterval(32 * 24 * 60 * 60)
        #expect(allowance.access == .pro(remainingThisMonth: 100))
    }

    @Test func remembersUsageAcrossLaunches() {
        GenerationAllowance(defaults: defaults, enforcesLimits: true).recordGeneration()
        #expect(GenerationAllowance(defaults: defaults, enforcesLimits: true).access == .free(remaining: 4))
    }

    @Test func testingModeSkipsEveryLimit() {
        let allowance = GenerationAllowance(defaults: defaults, enforcesLimits: false)
        for _ in 0..<50 { allowance.recordGeneration() }
        #expect(allowance.access == .unlimited)
    }
}
