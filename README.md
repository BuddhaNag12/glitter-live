<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Branding/GlitterLive-Logo-Horizontal-Dark-Transparent.png">
    <img src="Branding/GlitterLive-Logo-Horizontal-Light-Transparent.png" alt="Glitter Live" width="420">
  </picture>
</p>

<p align="center">
  Turn any video into a Live Photo wallpaper that moves every time you wake your iPhone.
</p>

<p align="center">
  <img src="docs/screenshots/onboarding-1-dark.png" width="200" alt="Welcome screen">
  <img src="docs/screenshots/explore-dark.png" width="200" alt="Explore catalog">
  <img src="docs/screenshots/explore-detail-dark.png" width="200" alt="Wallpaper detail">
  <img src="docs/screenshots/convert-empty-dark.png" width="200" alt="Convert a video">
</p>
<p align="center">
  <img src="docs/screenshots/trim-studio-dark.png" width="200" alt="Trim Studio preview">
  <img src="docs/screenshots/trim-studio-3-dark.png" width="200" alt="Trim Studio controls">
  <img src="docs/screenshots/result-dark.png" width="200" alt="Saved Live Photo">
  <img src="docs/screenshots/library-grid-dark.png" width="200" alt="Library">
</p>

<details>
<summary>Light mode</summary>
<p align="center">
  <img src="docs/screenshots/onboarding-1-light.png" width="200" alt="Welcome screen, light">
  <img src="docs/screenshots/explore-light.png" width="200" alt="Explore catalog, light">
  <img src="docs/screenshots/explore-detail-light.png" width="200" alt="Wallpaper detail, light">
  <img src="docs/screenshots/convert-empty-light.png" width="200" alt="Convert a video, light">
</p>
<p align="center">
  <img src="docs/screenshots/trim-studio-light.png" width="200" alt="Trim Studio preview, light">
  <img src="docs/screenshots/trim-studio-3-light.png" width="200" alt="Trim Studio controls, light">
  <img src="docs/screenshots/result-light.png" width="200" alt="Saved Live Photo, light">
  <img src="docs/screenshots/library-grid-light.png" width="200" alt="Library, light">
</p>
</details>

## Features

- **Explore**: the first tab, a curated catalog of live wallpapers, served from Supabase, that saves to Photos as a Lock Screen-ready Live Photo in one tap. It opens on a playing Featured wallpaper, and touching and holding any wallpaper previews its motion. While the catalog loads, shimmering placeholders hold the page's shape, and the cards rise into place in a wave when it arrives.
- **Video to Live Wallpaper**: pick any video, trim a 1–3 second moment, and save it as a Live Photo that plays on the Lock Screen when the iPhone wakes.
- **Trim Studio**: filmstrip with trim handles that preview the frame under your finger and stretch softly at their limits, a draggable cover-frame marker, pinch-and-drag framing inside a Lock Screen preview (clock, widgets and quick actions) that springs back with your finger's momentum, 0.5×–2× speed and a forward-and-back bounce.
- **Sharp cover photo**: the still shown while the phone is locked is rendered from the original video at up to 1320 px wide, sharper than the motion clip.
- **Library**: every wallpaper is kept in the app, so it can be previewed, saved to Photos again or deleted.
- **Private by design**: only asks to *add* photos, never reads the library, and collects no data.
- **Silver Shimmer design**: light and dark modes that follow the system, an obsidian dark mode lit by brand blue and silver, softly twinkling glitter, and native Liquid Glass on iOS 26+ with frosted fallbacks on iOS 17–25. A logo reveal plays as the app launches.
- **Accessible**: Dynamic Type with size-tuned letter-spacing, Reduce Motion, Increase Contrast and Reduce Transparency are all supported.
- Free, with no watermark.

## Lock Screen motion

Photos accepts any still and movie that share a content identifier as a Live Photo. The Lock Screen's wallpaper editor is stricter, and reports *"Motion Not Available"* unless the movie meets extra, undocumented requirements. Glitter Live writes:

- 8-bit HEVC video with the long side at most 1920 px and a duration of 5 s or less
- a `live-photo-info` timed-metadata track, one sample per frame
- a `still-image-time` + `live-photo-still-image-transform` sample at the cover frame, in the 600 timescale and never at 0 s
- a cover photo that shows the same frame as the movie (it may be larger)

See [`LivePhotoBuilder.swift`](LiveWall/Core/LivePhoto/LivePhotoBuilder.swift) and [`LivePhotoMetadata.swift`](LiveWall/Core/LivePhoto/LivePhotoMetadata.swift).

## Catalog backend

Explore reads the `wallpapers` table (read-only for the app's publishable key) and downloads files from a public Supabase Storage bucket. To add a wallpaper:

```bash
cp scripts/storage.env.example scripts/storage.env   # fill in the S3 and secret keys; this file is git-ignored
scripts/upload-wallpaper.sh ~/Movies/loop.mp4 --title "Neon Rain" --category "Abstract" --creator "Your Name"
```

The table is created by [`supabase/migrations/0001_wallpapers.sql`](supabase/migrations/0001_wallpapers.sql).

## Requirements

- iOS 17 or later (Lock Screen Live Photo motion needs iOS 17+)
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Getting started

```bash
brew install xcodegen
xcodegen generate
open LiveWall.xcodeproj
```

Set your own development team in `project.yml` (`DEVELOPMENT_TEAM`), or under Signing & Capabilities in Xcode, then run on an iPhone. The Simulator can't show Lock Screen wallpapers, so test motion on a real device.

## Tests

```bash
xcodebuild test -project LiveWall.xcodeproj -scheme LiveWall \
  -destination 'platform=iOS,name=<your iPhone>' -only-testing:LiveWallTests
```

- `LiveWallTests`: Live Photo pairing, required metadata tracks, output size and length, speed and bounce, cover-photo resolution and frame match, and the Library.
- `LiveWallUITests`: launches each screen with demo content (`-demoVideo`, `-demoResult`, `-demoLibrary`) and attaches screenshots to the test result.

## Project structure

```
LiveWall/
  App/            App entry point, tab bar and launch intro
  Core/LivePhoto/ Video → Live Photo pipeline, saving and preview
  DesignSystem/   Colors, type, glass components, motion, logo artwork, Lock Screen overlay
  Core/Catalog/   Supabase catalog client and downloads
  Features/       Explore, Convert, Library, Onboarding, Settings
  Resources/      Assets, fonts, privacy manifest
LiveWallTests/    Unit tests
LiveWallUITests/  On-device screenshot tests
Branding/         Logo files, layered SVGs and the Jitter logo reveal
docs/             Privacy policy, support page, App Store listing, screenshots
scripts/          Icon, logo and SVG renderer, wallpaper upload tools
supabase/         Database migrations
```

## Roadmap

### 1.0: built, not yet submitted

- [x] Video to Live Wallpaper with Trim Studio, Library and Explore
- [x] Design pass on Apple's fluid-interface guidance: interruptible springs, momentum, rubber-banding, press feedback, card-to-detail zoom transitions and consistent haptics
- [x] Accessibility: Dynamic Type, Reduce Motion, Increase Contrast and Reduce Transparency
- [x] Launch logo reveal
- [x] Explore: playing Featured wallpaper and touch-and-hold motion preview
- [x] Release prep: version 1.0.0, [privacy policy](docs/privacy.md), [support page](docs/support.md) and [App Store listing](docs/app-store.md)
- [x] Launch time measured at about 270 ms to first frame on an iPhone 17 Pro
- [ ] App Store submission: 6.9" screenshots, archive and upload
- [ ] Refresh the README screenshots for the latest design

### Next

- **Create**: generate live wallpapers from a text prompt or a photo. Only a teaser screen exists so far, hidden behind `FeatureFlags.aiGeneration` until generation works end to end. Needs an AI video provider, a small server that keeps the provider's key out of the app, generation limits, and the Create screen from the design mockups.
- **Pricing**: decide between the original plan (the first 3 generations free, then a short ad per generation or a one-time **Lifetime** purchase at ₹399) and the paywall mockup (weekly or yearly subscription plus credit packs).
- **Explore extras** from the mockup: search, sort by New, and later like counts and Free/VIP badges (likes need backend support; badges need pricing).
- **Trim Studio**: video stabilization (the mockup's Stabilize toggle).
- **Smoothness**: profile scrolling with Instruments. 120 Hz on ProMotion and pausing background effects on hidden tabs are done.

## Acknowledgements

- [LivePaper](https://github.com/Yuyang16Z/LivePaper) (MIT) for documenting the Lock Screen's Live Photo requirements. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- [Inter](https://rsms.me/inter/) typeface (SIL Open Font License).

## License

Glitter Live is released under the [MIT License](LICENSE). The bundled Inter font files keep their own SIL Open Font License, and third-party notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
