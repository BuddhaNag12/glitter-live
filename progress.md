# Progress

Last updated 2026-10-13. `main` at the merge of #21. Version 1.0.0.

## Status

**Convert is ready to release in code.** Release waits on the Apple Developer Program enrollment. Create works but isn't ready to ship (see Next).

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

The developer website (https://buddhanag12.github.io) and its `app-ads.txt` are live.

## Waiting on enrollment

1. Change `DEVELOPMENT_TEAM` in `project.yml` to the paid team's ID and rebuild with `-allowProvisioningUpdates`.
2. App Store Connect: create the app, sign the Paid Apps agreement, create the in-app purchase. Listing text is in [app-store.md](app-store.md).
3. Xcode Cloud: create the workflow and add the `GAD_APPLICATION_ID` and `GAD_REWARDED_AD_UNIT_ID` secrets (release checklist step 6).
4. AdMob: the EU/UK consent message; after launch, link the app and check `app-ads.txt`.
5. Archive, fill in App Privacy from the privacy report, submit with the in-app purchase, then tag `v1.0.0`.

## Next

1. **Ship Create**: server-side limits (DeviceCheck for the free generations, AdMob server-side verification, a StoreKit check for Pro), the Pro subscription and paywall, Create's privacy answers, Cloudflare Workers Paid. Then turn on its feature flags.
2. **App Store metadata in the repo**: listing, "What's New" and screenshots uploaded on each release tag (needs an App Store Connect API key).
3. **Competitor research**: pricing, ratings and review complaints of similar apps.
4. **Trim Studio on the iPhone SE**: the preview runs under the tab bar.
5. **AI video motion**: needs a paid provider (fal, WaveSpeed, Creative Fabrica at about $0.43 per video) or self-hosting.

## Backlog

- Explore search and sort by newest
- Refresh the README and App Store screenshots
- Warm up the depth model before first use
- Scroll performance profiling
- The shared screen header truncates "Convert" at the largest text sizes
- Delete merged remote branches (keep `design-glacier`)

## Notes

- CI skips the four test suites that encode video; GitHub's runners have no GPU and they take over 25 minutes there. Run the full suite locally before a release (30 tests, about 4 minutes):
  `xcodebuild test -project LiveWall.xcodeproj -scheme LiveWall -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LiveWallTests -collect-test-diagnostics never`
- Releasing: bump `MARKETING_VERSION` in a pull request, merge, then `git tag vX.Y.Z && git push origin vX.Y.Z`.
