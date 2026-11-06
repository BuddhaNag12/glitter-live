# Progress

Last updated 2026-11-06. Version 1.0.0 is live on the App Store.

## Status

**Glitter Live 1.0 is live on the App Store (2026-11-06).** Build 1.0.0 (10) with the Unlimited Conversions purchase. App Review's only query (guideline 2.1: the tracking prompt only appeared at the first ad) was fixed in #29 by asking right after onboarding. Real ads are serving; AdMob still lists the app as Requires review until its crawler verifies `app-ads.txt` (up to 7 days after the first ad requests). Create is in TestFlight beta only (see Next).

## Done

| PR | What |
| --- | --- |
| #13 | Convert limits: 5 free conversions, then a rewarded ad per video or the one-time unlock |
| #14 | AdMob rewarded ads with Google's consent form and the tracking prompt |
| #15 | Video sources: Files, Paste Link, and the Share extension |
| #16 | Onboarding, the Set as Wallpaper guide, the one-screen Convert hero |
| #17 | Motion polish: unlock celebration, hero to Trim Studio transition, badge tick |
| #18 | Release docs: privacy policy, support page, App Store listing, review notes |
| #19 | Real AdMob IDs from the uncommitted `Config/AdMob.secrets.xcconfig` |
| #20 | Bounce saves no longer fail; cover frame kept 0.5 s or later so Lock Screen motion works; result screen fits the iPhone SE |
| #21 | CI on every pull request, automatic deploys of the `generate` function, tagged GitHub releases |
| #22 | Ignore `graphify-out` |
| #23 | App Review fixes: build number 2, the ad SDK starts on the first chosen ad (after consent and tracking prompts), max ad content rating G; GitHub Actions build removed in favour of Xcode Cloud |
| #24 | README: Xcode Cloud builds every push to `main` |
| #25 | `Package.resolved` tracked so Xcode Cloud can resolve packages; post-clone script tolerates a preinstalled Metal Toolchain |
| #26 | App Store screenshots (6.9" and 6.3"), product page header and search asset from `scripts/render-icon.swift store`; `-releaseFeatures` hides Create in screenshot runs |
| #27 | AI beta: `AI_BETA=1` Xcode Cloud workflow turns Create on for TestFlight builds only |
| #28 | Create ready for external testers: AI notice before the first generation, no Pro wording, privacy policy section |
| #29 | Tracking prompt right after onboarding (App Review 2.1) |
| #30 | Friendlier AI notice without naming the provider |

The developer website (https://buddhanag12.github.io) and its `app-ads.txt` are live.

## After launch

1. AdMob: `app-ads.txt` verification (automatic). Don't watch or tap ads in the App Store build; use a test device for ad testing.
2. Supabase: the free tier pauses after about a week without traffic (it did once during review). Upgrade to Pro or add a scheduled ping.
3. EU: DSA trader verification, then add the EU countries back if they were removed.
4. Explore: nothing is in the `Featured` category since Coastal Ride was removed.
5. Dark-mode flicker when switching tabs after changing appearance: needs a recording from a real iPhone (not reproducible in the simulator).

## Next

1. **Ship Create**: server-side limits (DeviceCheck for the free generations, AdMob server-side verification, a StoreKit check for Pro), the Pro subscription and paywall, Create's privacy answers, Cloudflare Workers Paid. Then turn on its feature flags.
2. **App Store metadata in the repo**: listing, "What's New" and screenshots uploaded on each release tag (needs an App Store Connect API key).
3. **Competitor research**: pricing, ratings and review complaints of similar apps.
4. **Trim Studio on the iPhone SE**: the preview runs under the tab bar.
5. **AI video motion**: needs a paid provider (fal, WaveSpeed, Creative Fabrica at about $0.43 per video) or self-hosting.

## Backlog

- Explore search and sort by newest
- Refresh the README screenshots
- App preview video (optional)
- Warm up the depth model before first use
- Scroll performance profiling
- The shared screen header truncates "Convert" at the largest text sizes
- Delete merged remote branches (keep `design-glacier`)

## Notes

- No CI runs tests now; run the full suite locally before a release (30 tests, about 4 minutes):
  `xcodebuild test -project LiveWall.xcodeproj -scheme LiveWall -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LiveWallTests -collect-test-diagnostics never`
- Releasing: bump `MARKETING_VERSION` in a pull request and merge it. The Release workflow tags `vX.Y.Z` and creates the GitHub release; Xcode Cloud sends the build to TestFlight.
- Xcode 27.1 can fail to create Xcode Cloud workflows ("Could not find item", or asking to connect the `googleads` org). Luminux's workflow was created by generating its project without the Google packages just for the setup.
