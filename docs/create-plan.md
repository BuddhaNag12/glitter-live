# Create: AI live wallpapers

Plan for the Create tab: type a prompt and get a wallpaper image, then save it as it is or add motion to make it a Live Photo wallpaper.

## Flow

1. **Prompt**: describe a scene and pick a style from the menu in the prompt card. "Surprise Me" cycles through 100 prompts without repeats.
2. **Image**: "Generate Wallpaper" makes only the image (FLUX.1 schnell, about 10 seconds). This is the step that counts as a generation.
3. **Your wallpaper**: the image on a Lock Screen preview, with:
   - **Save Wallpaper**: a 9:16 still in Photos, then "Set as Wallpaper" opens the guide.
   - **Add Motion**: depth parallax made on the phone (Apple's Depth Anything V2), free and about a second on device.
   - **Try Again** (same prompt, new image) and **Edit Prompt**.
4. **Live preview**: **Save Live Wallpaper** keeps it in the Library and Photos; **Edit Motion** opens Trim Studio; **Back to Still** returns to step 3.

When AI motion is available (`FeatureFlags.aiMotion`), Add Motion can offer it alongside the free depth motion, for example as a Pro option.

## Pricing: one subscription

| | Free | Glitter Live Pro |
|---|---|---|
| Explore, Library | Free, no ads | Free, no ads |
| Convert | First 5 free, then one rewarded ad per video, or the one-time Unlimited Conversions purchase | Same as Free (Pro covers Create only) |
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
| Image | FLUX.1 schnell (1024 px square) | Apache 2.0 | Cloudflare Workers AI (free tier, about 170 images a day) |
| Video | LTX-Video 13B distilled, 9:16 at 720p, 73 frames at 24 fps | LTX licence, free under $10M company revenue | Hosted at first (fal.ai `fal-ai/ltx-video-13b-distilled/image-to-video`), then a self-hosted GPU once volume justifies it |
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

## Server

`supabase/functions/generate` is deployed with `--no-verify-jwt`, because the app sends the publishable key rather than a user JWT. Provider keys are Supabase secrets: `CLOUDFLARE_ACCOUNT_ID` (the 32-character account ID, not the login email), `CLOUDFLARE_AI_TOKEN` and `FAL_KEY`.

```bash
supabase functions deploy generate --no-verify-jwt --use-api --project-ref jusrioirjfpaocgmsbbv
```

Before release, the function must enforce the limits itself (DeviceCheck for the free generations, ad tokens, Pro status), since today anyone with the publishable key could call it.

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
