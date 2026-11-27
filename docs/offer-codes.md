# Free unlimited conversions with offer codes

Glitter Live's "Unlimited conversions" (`com.buddhanag.glitterlive.convert.unlimited`) is a non-consumable. Apple's **offer codes** cover it: make a "free offer" in App Store Connect, hand out codes, and anyone who redeems one owns the unlock exactly as if they'd bought it (restores on every device, never expires). Offer codes are Apple's current way to do this (the old promo codes help page no longer exists).

Same setup as Luminux (`luminux/docs/offer-codes.md`, done 2026-11-23). Apple's docs:
[Create offer codes for In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases),
[Supporting offer codes in your app](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app).

## What already works, what needs code

- **Codes redeemed outside the app** (App Store app → account → Redeem, or a redemption link) already unlock: `Purchases` listens to `Transaction.updates` and checks `currentEntitlements` on `load()`. No new build needed for one-time codes.
- **Custom codes** (e.g. `GLITTERFREE`) can only be redeemed inside an app or through a link, not typed in the App Store app. Add an in-app "Redeem code" (below) so people can type one.
- Redeeming needs iOS 16.3 or later; Glitter Live needs 17, so everyone can.

## Code change (small)

`LiveWall/Core/Store/Purchases.swift`: let a redemption that arrives through `updates` celebrate like a purchase. In `init`, replace the loop body:

```swift
for await update in Transaction.updates {
    if case .verified(let transaction) = update { await transaction.finish() }
    guard let self else { return }
    let ownedBefore = self.ownsUnlimitedConversions
    await self.refreshEntitlements()
    // An offer code (or Ask to Buy approval) unlocks here rather than through buyUnlimitedConversions().
    if self.ownsUnlimitedConversions && !ownedBefore { self.unlockCount += 1 }
}
```

`LiveWall/Features/Settings/SettingsView.swift`: a row under "Restore purchases" in `purchaseRows`, plus `@State private var isRedeeming = false` on the view:

```swift
rowDivider
row("Redeem code", symbol: "giftcard.fill", tint: WallpaperPalette.rose) {
    isRedeeming = true
}
.offerCodeRedemption(isPresented: $isRedeeming) { _ in
    // If the sheet couldn't open, this lets the next tap try again.
    isRedeeming = false
    // The transaction also arrives through Transaction.updates; this just doesn't wait for it.
    Task { await purchases.load() }
}
```

(Pick whichever symbol and tint fit the other rows. `offerCodeRedemption(isPresented:onCompletion:)` is iOS 16+; with the iOS 27 SDK it's deprecated in favour of `offerCodeRedemption(options:isPresented:onCompletion:)`, but there's no warning while the deployment target is below 27.)

Optional: the same "Redeem code" text button under "Restore Purchase" in `UnlockConversionsSheet`, calling `onChoose(.unlocked)` when `purchases.ownsUnlimitedConversions` turns true.

The simulator doesn't show the redemption sheet; test on a device (below).

## Kinds of code

| | One-time-use | Custom (e.g. `GLITTERFREE`) | Sandbox |
|---|---|---|---|
| Who | one person per code | many people, up to a limit you set | testing only |
| Batch | 500 to 25,000 random codes | redemption limit up to 25,000 per batch | 10 to 10,000 |
| Expiry | required, up to 6 months | optional (up to 6 months, or no end date) | optional |
| Redeem via | link, App Store app, or in the app | link or in the app | Sandbox account settings, or in the app |

Limits per app: 10 active offers, 1 million codes a quarter. One redemption per person per offer. Offers can't be edited (make a new one); codes can be deactivated any time and people who redeemed keep the unlock. New codes can take up to an hour to work.

For a few people, a **custom code with a small limit** is simplest.

## Set it up in App Store Connect

Needs the app Ready for Distribution and the IAP Approved (sandbox codes work regardless). Roles: Account Holder, Admin, App Manager or Marketing.

1. Apps → Glitter Live → **In-App Purchases** → Unlimited conversions.
2. **Offer Codes** → **Create Offer**.
3. Reference name, e.g. `Free Unlimited 2026` (can't be reused or renamed).
4. Eligibility: tick all three for "anyone", or just "never purchased".
5. Countries or regions: all.
6. **Free Offer** → Next → Confirm.
7. Open the offer:
   - **Custom code:** Create Custom Codes → code (letters and numbers, up to 64), redemption limit, expiry or No End Date → Create.
   - **One-time codes:** Create One-Time Use Codes → how many (min 500), expiry → Create → **Download** the CSV.
   - **Sandbox codes:** Create Sandbox Codes (for the test below).

## Sharing a code

- In the app: Settings → **Redeem code** (after the build above), or App Store app → your photo → **Redeem Gift Card or Code** (one-time codes only).
- Or a link: `https://apps.apple.com/redeem?ctx=offercodes&id=<Glitter Live's Apple ID>&code=GLITTERFREE` (App Store Connect shows each code's link; prefer that one).

## Test

1. Create sandbox codes on the offer.
2. On a device: Settings → Developer → Sandbox Apple Account, sign in.
3. Install a TestFlight or Xcode build, open Settings → Redeem code, enter a sandbox code: Convert unlocks and the celebration plays.
4. Also: Sandbox Account Settings → Initiate Transaction → Offer Codes with the app closed, then open the app.
5. If a sandbox account can't redeem again, clear its purchase history.

Mention "Redeem code" in the review notes of the build that adds it.
