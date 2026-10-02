import Foundation
import Testing
@testable import LiveWall

@MainActor
struct ConversionAllowanceTests {
    private let defaults = UserDefaults(suiteName: "ConversionAllowanceTests-\(UUID().uuidString)")!

    @Test func startsWithFiveFreeThenAsksForAnAd() {
        let allowance = ConversionAllowance(defaults: defaults, enforcesLimits: true)
        #expect(allowance.access == .free(remaining: 5))
        for _ in 0..<5 { allowance.recordFreeConversion() }
        #expect(allowance.access == .ad)
        allowance.recordFreeConversion()
        #expect(allowance.freeUsed == 5)
    }

    @Test func unlockSkipsTheLimit() {
        let allowance = ConversionAllowance(defaults: defaults, enforcesLimits: true)
        for _ in 0..<5 { allowance.recordFreeConversion() }
        allowance.isUnlocked = true
        #expect(allowance.access == .unlocked)
    }

    @Test func remembersUsageAcrossLaunches() {
        ConversionAllowance(defaults: defaults, enforcesLimits: true).recordFreeConversion()
        #expect(ConversionAllowance(defaults: defaults, enforcesLimits: true).access == .free(remaining: 4))
    }

    @Test func limitsOffSkipsEverything() {
        let allowance = ConversionAllowance(defaults: defaults, enforcesLimits: false)
        for _ in 0..<10 { allowance.recordFreeConversion() }
        #expect(allowance.access == .unlimited)
    }

    @Test func editorAsksForPaymentOnlyOnceTheFreeOnesAreUsed() {
        let allowance = ConversionAllowance(defaults: defaults, enforcesLimits: true)
        let video = URL(filePath: "/dev/null")
        #expect(!ConvertEditor(sourceURL: video, allowance: allowance).needsPayment)

        for _ in 0..<5 { allowance.recordFreeConversion() }
        let editor = ConvertEditor(sourceURL: video, allowance: allowance)
        #expect(editor.needsPayment)
        editor.adWatched()
        #expect(!editor.needsPayment)

        // Create's generated videos are never limited.
        #expect(!ConvertEditor(sourceURL: video).needsPayment)
    }
}
