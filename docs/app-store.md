# App Store listing: Glitter Live 1.0

Copy for App Store Connect. Character limits are Apple's; counts are noted where they're tight.

## App information

| Field | Value |
| --- | --- |
| Name (30) | Glitter Live |
| Subtitle (30) | Video to Live Wallpaper (23) |
| Primary category | Photo & Video |
| Secondary category | Lifestyle |
| Age rating | 4+ |
| Price | Free, with an in-app purchase |
| Copyright | 2026 Buddha Nag |
| Privacy Policy URL | https://github.com/BuddhaNag12/glitter-live/blob/main/docs/privacy.md |
| Support URL | https://github.com/BuddhaNag12/glitter-live/blob/main/docs/support.md |

## Promotional text (170)

Turn any video into a Live Photo wallpaper that moves every time you wake your iPhone. Trim, frame and save in seconds, with no watermark.

## Description (4000)

Your Lock Screen, in motion. Glitter Live turns a moment from any video into a Live Photo wallpaper that comes alive every time you wake your iPhone.

TRIM STUDIO
• Drag the handles to pick the exact 1–3 seconds you want, with the frame under your finger shown as you go
• Pinch and drag to frame the video around the clock and widgets, in a live Lock Screen preview
• Choose the cover photo shown while your iPhone is asleep
• Slow it down to 0.5× or speed it up to 2×, or make it bounce back and forth

READY FOR THE LOCK SCREEN
Glitter Live writes Live Photos the way the Lock Screen expects, so your wallpaper actually moves. The cover photo is rendered from the original video at full screen resolution, sharper than the motion clip.

BRING ANY VIDEO
Pick from Photos or Files, paste a direct link (Dropbox and Google Drive work too), or share a video to Glitter Live from another app.

EXPLORE
Browse hand-picked live wallpapers, touch and hold any of them to preview its motion, and save one in a tap.

YOUR LIBRARY
Every wallpaper you make is kept in the app, so you can preview it, save it to Photos again or delete it.

PRIVATE BY DESIGN
• Your videos are processed on your iPhone and never uploaded
• Glitter Live only asks to add photos; it can't see your library
• No account needed

FREE TO TRY
Explore is free, and so are your first 5 conversions. After that, each conversion is free with a short ad you choose to watch, or unlock Unlimited Conversions once to remove the limit and the ads. There's never a watermark.

## Keywords (100)

lock screen,lockscreen,photo,motion,moving,animated,background,theme,aesthetic,trim,loop,clip,wake

(98 characters. "Glitter", "Live", "Video" and "Wallpaper" are left out because the name and subtitle already cover them, and search combines all three, so "live photo" and "video wallpaper" still match.)

## What's New (version 1.0.0)

The first release of Glitter Live.

## In-app purchase

| Field | Value |
| --- | --- |
| Type | Non-Consumable |
| Reference name | Unlimited Conversions |
| Product ID | `com.buddhanag.glitterlive.convert.unlimited` |
| Price | Your choice; the app shows whatever App Store Connect sets (₹199 is the local test price) |
| Family Sharing | On |
| Display name (30) | Unlimited Conversions (21) |
| Description (45) | Convert as many videos as you like, no ads. (43) |
| Review screenshot | The unlock sheet: convert 5 videos, then tap Save in Trim Studio |
| Review notes | Removes Convert's 5-conversion limit and its rewarded ads. Restore is in Settings. |

## App Privacy

These come from the privacy manifests inside Google Mobile Ads 13.11 and Google's User Messaging Platform 3.1, the only parts of the app that collect data. Converted videos stay on the device, and Explore only downloads catalog files.

**Data used to track you**

| Data type | Purposes |
| --- | --- |
| Identifiers → Device ID | Third-Party Advertising, Developer's Advertising or Marketing, Analytics |

**Data linked to you**

| Data type | Purposes |
| --- | --- |
| Identifiers → Device ID | Third-Party Advertising, Developer's Advertising or Marketing, Analytics |
| Location → Coarse Location | Third-Party Advertising, Developer's Advertising or Marketing, Analytics, App Functionality |
| Usage Data → Advertising Data | Third-Party Advertising, Developer's Advertising or Marketing, Analytics |
| Usage Data → Product Interaction | Third-Party Advertising, Developer's Advertising or Marketing, Analytics, App Functionality |

**Data not linked to you**

| Data type | Purposes |
| --- | --- |
| Diagnostics → Crash Data | Analytics |
| Diagnostics → Performance Data | Third-Party Advertising, Developer's Advertising or Marketing, Analytics, App Functionality |
| Diagnostics → Other Diagnostic Data | Third-Party Advertising, Developer's Advertising or Marketing, Analytics |

Purchases aren't declared: Apple processes them, and the app only checks whether the unlock is owned.

Before submitting, check these against the privacy report Xcode builds from the archive (Organizer → right-click the archive → Generate Privacy Report). It merges every manifest in the app and is what Apple compares against.

## App Review notes

- No sign-in is needed.
- Glitter Live asks for add-only Photos access the first time a wallpaper is saved; it never reads the library.
- Explore needs an internet connection. Convert works offline: tap Choose from Photos, pick any video, then Save Live Photo.
- The first 5 conversions are free. After that, Save in Trim Studio offers a rewarded ad or the Unlimited Conversions purchase. Ads never appear on their own. Restore Purchases is in Settings.
- The App Tracking Transparency prompt appears only when the reviewer first chooses to watch an ad.
- Paste Link downloads direct links to video files only. Links to YouTube, Instagram and similar sites are refused with steps for saving the video from that app instead, so the app doesn't download media from third-party services.
- To check Lock Screen motion: in Photos, open the saved Live Photo, tap Share → Use as Wallpaper, make sure the Live Photo button is on, then Add. The app explains these steps under "How to set a live wallpaper" in Settings.

## Screenshots

iPhone only (the app is iPhone-only). App Store Connect needs the 6.9" size, 1320 × 2868, which the iPhone 18 Pro Max simulator produces. The screenshot UI test captures every screen in light and dark:

```bash
xcodebuild test -project LiveWall.xcodeproj -scheme LiveWall -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:LiveWallUITests
```

Suggested order: Explore, Trim Studio, Trim Studio controls, Result, Library, Onboarding welcome.

## Release checklist

Everything in the app is ready; these are the account steps, in order.

1. **AdMob**: add the app (iOS, linked to the App Store listing once it exists), create one **Rewarded** ad unit, and set the app's maximum ad content rating to **G** so the 4+ age rating holds. Send the app ID (`ca-app-pub-…~…`) and the ad unit ID (`ca-app-pub-…/…`); both are public and end up inside the app.
2. **AdMob → Privacy & messaging**: create a **European regulations** (GDPR) message for the app, so the consent form appears in the EU and UK. Optionally add an **IDFA explainer** before the tracking prompt.
3. **app-ads.txt**: AdMob verifies the app through an `app-ads.txt` file at the root of the developer website listed on the App Store page. GitHub blob links can't serve one, so publish it with GitHub Pages (a repository named `BuddhaNag12.github.io`) and use that site as the Marketing URL.
4. **App Store Connect**: sign the Paid Apps agreement and add banking and tax details, then create the in-app purchase above with its review screenshot.
5. **In the app**: done. The real IDs are in `Config/AdMob.secrets.xcconfig`, which isn't committed because the repository is public; keep a copy somewhere safe, since a release built without it shows no ads.
6. **Archive**, generate the privacy report, fill in App Privacy from it, and submit the build together with the in-app purchase.

