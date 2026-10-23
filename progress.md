# Progress

Last updated 2026-10-23. `main` at the merge of #25; store assets on the `store-assets` branch (PR open). Version 1.0.0.

## Status

**1.0 is in App Review (submitted 2026-10-23).** Build 1.0.0 (6) from Xcode Cloud, with real AdMob IDs (test ad confirmed on a device), and the Unlimited Conversions in-app purchase. App Privacy, age rating 4+, content rights, listing text, screenshots, header and search assets are all in App Store Connect. Create works but isn't ready to ship (see Next).

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
| `store-assets` | App Store screenshots (6.9" and 6.3"), product page header and search asset from `scripts/render-icon.swift store`; `-releaseFeatures` hides Create in screenshot runs |

The developer website (https://buddhanag12.github.io) and its `app-ads.txt` are live.

## In review

Check App Store Connect → App Review for questions or a rejection. Keep the Explore catalog published while it's in review.

Not confirmed when submitting: the Paid Apps agreement is **Active** (tax form), the AdMob EU/UK consent message is published, and China mainland (no ICP filing) and the EU (DSA trader verification pending) are out of availability if needed.

## After approval

1. Release (if manual), then `git tag v1.0.0 && git push origin v1.0.0`.
2. AdMob: link the App Store listing so real ads serve, check `app-ads.txt`, and remove the test iPhone from Test devices.
3. Merge the `store-assets` PR; delete the local `review-screenshots/` folder.
4. Move a wallpaper into the `Featured` category; that filter is empty since Coastal Ride (Nike logo) was removed.

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
- Releasing: every merge to `main` goes to TestFlight through Xcode Cloud (it sets the build number). For a release, bump `MARKETING_VERSION` in a pull request, merge, then `git tag vX.Y.Z && git push origin vX.Y.Z` for the GitHub release.
- Xcode 27.1 can fail to create Xcode Cloud workflows ("Could not find item", or asking to connect the `googleads` org). Luminux's workflow was created by generating its project without the Google packages just for the setup.
