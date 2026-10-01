# Create: AI live wallpapers

Plan for the Create tab: type a prompt, get a wallpaper image, bring it to life as a 3-second video, and save it as a Live Photo wallpaper in one step.

## Flow

1. **Prompt**: describe a scene and pick a style. "Surprise Me" fills in an example.
2. **Image**: the server generates a sharp 9:16 wallpaper with FLUX.1 schnell. It can be saved as a still wallpaper.
3. **Motion**: "Bring to Life" animates that image into a 3-second clip with LTX-Video.
4. **Convert on the go** (on by default): the clip goes straight through the existing Live Photo pipeline and is saved to the Library and Photos as a Lock Screen-ready Live Photo. The generated image becomes the Lock Screen still, so it's sharper than a frame from the video.
5. **Fine-tune**: "Edit in Trim Studio" opens the clip for speed, bounce and framing.

## Pricing: one subscription

| | Free | Glitter Live Pro |
|---|---|---|
| Explore, Convert, Library | Free, no ads | Free, no ads |
| AI generations | First 5 free, then one rewarded ad per generation | No ads, up to 100 a month |
| Daily limit | 10 ad generations a day | Covered by the monthly cap |
| Price | Free | ₹299 a month (one plan, auto-renewing) |

- Ads appear only on Create, only when the user taps "Watch Ad to Generate". No banners and no interstitials.
- The monthly and daily caps exist because each video costs money to generate.
- No accounts. Apple restores the subscription on any device. DeviceCheck lets the server remember that a phone has used its free generations, even after a reinstall.

### Why the numbers work

- An LTX clip costs about $0.01–0.02. A rewarded ad earns about $0.015 per view in the US, so ads roughly pay for free users' generations there. India pays less per view, which the daily limit keeps small.
- ₹299 leaves about ₹254 (≈ $2.90) after Apple's 15% Small Business commission. A subscriber using all 100 generations costs about $2.

## Models

| Step | Model | Licence | Where it runs |
|---|---|---|---|
| Image | FLUX.1 schnell | Apache 2.0 | Cloudflare Workers AI (free tier, about 170 images a day) |
| Video | LTX-Video, distilled | LTX licence, free under $10M company revenue | Hosted at first (fal.ai, about $0.02 a clip), then a self-hosted GPU once volume justifies it |
| Prompt safety | Llama Guard | Llama licence | Cloudflare Workers AI |

## Architecture

```
App ──► Supabase Edge Function `generate` ──► Cloudflare Workers AI (prompt check, FLUX image)
 │                 │                       └► LTX-Video (image to 3 s clip)
 │                 ├─ checks Pro (StoreKit 2 signed transaction)
 │                 ├─ checks free count (DeviceCheck) and ad tokens
 │                 └─ stores the image and clip in Supabase Storage, returns their URLs
 └─ AdMob rewarded ad ──► AdMob server-side verification callback ──► Edge Function `ad-reward`
```

The app never holds an AI provider key, and it never grants generations itself.

## Build order

1. **App: Create screen and on-the-go conversion**, against a `GenerationService` protocol with a demo implementation, so the whole flow can be built and tested on device before any accounts exist.
2. **Server**: Edge Functions `generate` and `ad-reward`, a `generation_usage` table, prompt checks.
3. **Subscription**: StoreKit 2 with a local `.storekit` configuration for testing, one auto-renewing product, a one-plan paywall.
4. **Ads**: Google Mobile Ads rewarded format, Google's consent SDK (UMP) for users in the EU and UK, App Tracking Transparency prompt.
5. **Privacy and listing**: update the App Store privacy label, `docs/privacy.md`, `docs/app-store.md` and the README's "collects no data" line. Create's prompts and ads collect data; Explore and Convert still don't.
6. Turn on `FeatureFlags.aiGeneration` for release.

## Accounts needed (owner to set up)

- **Cloudflare**: account and a Workers AI API token.
- **fal.ai**: API key for LTX-Video.
- **Google AdMob**: app registration, a rewarded ad unit, and the server-side verification URL.
- **App Store Connect**: the `Glitter Live Pro` monthly subscription product and the paid apps agreement.
- **Apple Developer**: a DeviceCheck key.
