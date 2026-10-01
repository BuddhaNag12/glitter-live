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
| Price | Free |
| Copyright | 2026 Buddha Nag |
| Privacy Policy URL | https://github.com/BuddhaNag12/glitter-live/blob/main/docs/privacy.md |
| Support URL | https://github.com/BuddhaNag12/glitter-live/blob/main/docs/support.md |

## Promotional text (170)

Turn any video into a Live Photo wallpaper that moves every time you wake your iPhone. Trim, frame and save in seconds. Free, no watermark.

## Description (4000)

Your Lock Screen, in motion. Glitter Live turns a moment from any video into a Live Photo wallpaper that comes alive every time you wake your iPhone.

TRIM STUDIO
• Drag the handles to pick the exact 1–3 seconds you want, with the frame under your finger shown as you go
• Pinch and drag to frame the video around the clock and widgets, in a live Lock Screen preview
• Choose the cover photo shown while your iPhone is asleep
• Slow it down to 0.5× or speed it up to 2×, or make it bounce back and forth

READY FOR THE LOCK SCREEN
Glitter Live writes Live Photos the way the Lock Screen expects, so your wallpaper actually moves. The cover photo is rendered from the original video at full screen resolution, sharper than the motion clip.

EXPLORE
Browse hand-picked live wallpapers, touch and hold any of them to preview its motion, and save one in a tap.

YOUR LIBRARY
Every wallpaper you make is kept in the app, so you can preview it, save it to Photos again or delete it.

PRIVATE BY DESIGN
• Your videos are processed on your iPhone and never uploaded
• Glitter Live only asks to add photos; it can't see your library
• No account, no tracking, no data collected

Free, with no watermark.

## Keywords (100)

lock screen,lockscreen,photo,motion,moving,animated,background,theme,aesthetic,trim,loop,clip,wake

(98 characters. "Glitter", "Live", "Video" and "Wallpaper" are left out because the name and subtitle already cover them, and search combines all three, so "live photo" and "video wallpaper" still match.)

## What's New (version 1.0.0)

The first release of Glitter Live.

## App Privacy

**Data Not Collected.** The app has no account, analytics, ads or tracking. Converted videos stay on the device; Explore only downloads catalog files.

## App Review notes

- No sign-in is needed.
- Glitter Live asks for add-only Photos access the first time a wallpaper is saved; it never reads the library.
- Explore needs an internet connection. Convert works offline: tap Choose Video, pick any video, then Save Live Photo.
- To check Lock Screen motion: in Photos, open the saved Live Photo, tap Share → Use as Wallpaper, make sure the Live Photo button is on, then Add. The app explains these steps under "How to set a live wallpaper" in Settings.

## Screenshots

iPhone only (the app is iPhone-only). App Store Connect needs the 6.9" size, 1320 × 2868, which the iPhone 18 Pro Max simulator produces. The screenshot UI test captures every screen in light and dark:

```bash
xcodebuild test -project LiveWall.xcodeproj -scheme LiveWall -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:LiveWallUITests
```

Suggested order: Explore, Trim Studio, Trim Studio controls, Result, Library, Onboarding welcome.
