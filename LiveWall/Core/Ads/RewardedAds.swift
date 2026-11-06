import AppTrackingTransparency
import GoogleMobileAds
import Observation
import os
import UIKit
import UserMessagingPlatform

/// Rewarded ads from AdMob. An ad plays only when someone chooses to watch one, never on its own.
@Observable
final class RewardedAds: NSObject, RewardedAdPresenter {
    static let shared = RewardedAds()

    /// From `GAD_REWARDED_AD_UNIT_ID` in Config/: Google's sample unit in debug, the real one in release.
    private static let adUnitID = Bundle.main.object(forInfoDictionaryKey: "GADRewardedAdUnitID") as? String ?? ""

    /// A release build still carrying Google's sample IDs would show "Test Ad" to real people and earn nothing,
    /// so it skips ads instead, as if none could be loaded.
    private static var hasRealAdUnit: Bool {
        #if DEBUG
        true
        #else
        !adUnitID.isEmpty && !adUnitID.hasPrefix("ca-app-pub-3940256099942544")
        #endif
    }

    /// Asking for consent or loading the ad, so the screen can say one is on its way.
    private(set) var isPreparing = false
    /// Where consent rules apply (EU, UK and others), people must be able to change their ad choices later, from Settings.
    private(set) var offersPrivacyChoices = false

    @ObservationIgnored private var loadedAd: RewardedAd?
    @ObservationIgnored private var hasGatheredConsent = false
    @ObservationIgnored private var hasStartedSDK = false
    @ObservationIgnored private var dismissal: CheckedContinuation<Bool, Never>?

    /// Refreshes consent quietly at launch, without showing any form, so Settings knows whether to offer privacy choices.
    /// The SDK itself waits for `askForPermissions()`, after the consent and tracking prompts.
    func warmUp() async {
        try? await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
        offersPrivacyChoices = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// Once onboarding is done: the consent form where the law requires it, then the tracking prompt, before the SDK
    /// starts. App Review expects the prompt up front rather than at the first ad, which can be five conversions away.
    func askForPermissions() async {
        guard Self.hasRealAdUnit else { return }
        #if DEBUG
        // Screenshot runs: system prompts would cover the screens.
        if ProcessInfo.processInfo.arguments.contains("-noPrompts") { return }
        #endif
        await gatherConsent()
    }

    /// Whether the ad was watched to the end. Callers decide what a missing ad means: Convert lets the
    /// conversion through, while Create can't generate without a reward the server has confirmed.
    func present(rewardID: String?) async -> AdOutcome {
        guard Self.hasRealAdUnit else { return .unavailable }
        guard !isPreparing, dismissal == nil else { return .closedEarly }
        isPreparing = true
        await gatherConsent()
        guard ConsentInformation.shared.canRequestAds, let ad = await readyAd() else {
            isPreparing = false
            return .unavailable
        }
        isPreparing = false
        loadedAd = nil

        // AdMob tells the server about the reward with these, signed by Google.
        let verification = ServerSideVerificationOptions()
        verification.userIdentifier = InstallID.value
        verification.customRewardText = rewardID
        ad.serverSideVerificationOptions = verification

        // Google doesn't promise the reward callback a thread, so it only flips a lock-protected flag.
        let earned = OSAllocatedUnfairLock(initialState: false)
        ad.fullScreenContentDelegate = self
        let presented = await withCheckedContinuation { continuation in
            dismissal = continuation
            ad.present(from: Self.topViewController) { @Sendable in earned.withLock { $0 = true } }
        }
        Task { _ = await readyAd() }
        guard presented else { return .unavailable }
        return earned.withLock { $0 } ? .watched : .closedEarly
    }

    func showPrivacyChoices() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: Self.topViewController)
    }

    /// Once per launch, as Google asks. The form only appears where the law requires it and consent is still needed.
    private func gatherConsent() async {
        if !hasGatheredConsent {
            do {
                try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
                try await ConsentForm.loadAndPresentIfRequired(from: Self.topViewController)
                hasGatheredConsent = true
            } catch {
                // The previous session's consent stays in effect; this is tried again next time.
            }
            offersPrivacyChoices = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        }
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        startSDKIfAllowed()
    }

    private func startSDKIfAllowed() {
        guard !hasStartedSDK, ConsentInformation.shared.canRequestAds else { return }
        hasStartedSDK = true
        // Keeps ads within the App Store age rating; raise it only if the rating goes up.
        MobileAds.shared.requestConfiguration.maxAdContentRating = .general
        MobileAds.shared.start(completionHandler: nil)
    }

    private func readyAd() async -> RewardedAd? {
        if let loadedAd { return loadedAd }
        guard hasStartedSDK else { return nil }
        loadedAd = try? await RewardedAd.load(with: Self.adUnitID, request: Request())
        return loadedAd
    }

    private static var topViewController: UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension RewardedAds: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        dismissal?.resume(returning: true)
        dismissal = nil
    }

    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        dismissal?.resume(returning: false)
        dismissal = nil
    }
}
