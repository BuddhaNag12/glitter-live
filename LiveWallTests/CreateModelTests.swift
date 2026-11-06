import Foundation
import Testing
@testable import LiveWall

/// Create spends a rewarded ad on each generation, and the server only generates for one it has confirmed.
@MainActor
struct CreateModelTests {
    private let allowance = GenerationAllowance(
        defaults: UserDefaults(suiteName: "CreateModelTests-\(UUID().uuidString)")!, enforcesLimits: true
    )

    @Test func aWatchedAdSendsItsRewardWithTheRequest() async {
        let ads = FakeAds(outcome: .watched)
        let service = RecordingService()
        let model = CreateModel(service: service, ads: ads, allowance: allowance)
        model.prompt = "A red fox in snow"
        await model.generate()
        #expect(service.requests.count == 1)
        #expect(service.requests.first?.reward == ads.lastRewardID)
        #expect(ads.lastRewardID != nil)
        #expect(allowance.access == .ad(remainingToday: 2))
    }

    @Test func closingTheAdEarlyGeneratesNothing() async {
        let service = RecordingService()
        let model = CreateModel(service: service, ads: FakeAds(outcome: .closedEarly), allowance: allowance)
        model.prompt = "A red fox in snow"
        await model.generate()
        #expect(service.requests.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func noAdAvailableExplainsAndGeneratesNothing() async {
        let service = RecordingService()
        let model = CreateModel(service: service, ads: FakeAds(outcome: .unavailable), allowance: allowance)
        model.prompt = "A red fox in snow"
        await model.generate()
        #expect(service.requests.isEmpty)
        #expect(model.errorMessage == "No ad is available right now. Try again in a minute.")
        #expect(allowance.access == .ad(remainingToday: 3))
    }
}

private final class FakeAds: RewardedAdPresenter {
    let outcome: AdOutcome
    private(set) var lastRewardID: String?

    init(outcome: AdOutcome) { self.outcome = outcome }

    func present(rewardID: String?) async -> AdOutcome {
        lastRewardID = rewardID
        return outcome
    }
}

private final class RecordingService: GenerationService, @unchecked Sendable {
    private(set) var requests: [GenerationRequest] = []

    func makeImage(for request: GenerationRequest) async throws -> URL {
        requests.append(request)
        let url = URL.temporaryDirectory.appending(path: "create-model-test-\(UUID().uuidString).jpg")
        try Data([0xFF]).write(to: url)
        return url
    }

    func animate(imageAt url: URL, for request: GenerationRequest) async throws -> URL { url }
}
