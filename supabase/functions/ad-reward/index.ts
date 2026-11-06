// AdMob's server-side verification callback: Google calls this when someone finishes a rewarded ad.
// Each verified reward lets `generate` make one AI wallpaper for the install that watched it.
//
//   GET ?ad_network=…&ad_unit=…&custom_data=<nonce>&…&transaction_id=…&user_id=<install>&signature=…&key_id=…
//
// Set this function's URL as the rewarded ad unit's SSV callback in AdMob. Deployed with --no-verify-jwt,
// since Google sends no Supabase key; the Google signature is what's checked.

import { verifierKeysURL, verifyRewardCallback } from "../_shared/admob.js";
import { database } from "../_shared/database.ts";

// Optional: only accept rewards from this ad unit (the number after the "/" in its ID).
const rewardedAdUnit = Deno.env.get("ADMOB_REWARDED_AD_UNIT") ?? "";

let keys: { keyId: number; base64: string }[] = [];

Deno.serve(async (request) => {
  const query = new URL(request.url).search.slice(1);
  try {
    if (!(await verified(query))) return new Response("Invalid signature.", { status: 400 });
    const params = new URLSearchParams(query);
    const nonce = params.get("custom_data") ?? "";
    const install = params.get("user_id") ?? "";
    const transaction = params.get("transaction_id") ?? "";
    // Convert's ads carry no nonce and AdMob's "Verify URL" test has no IDs: nothing to record, but still a 200.
    if (!nonce || !install || !transaction) return new Response("OK");
    if (rewardedAdUnit && params.get("ad_unit") !== rewardedAdUnit) return new Response("OK");
    if (nonce.length > 64 || install.length > 64) return new Response("Unexpected IDs.", { status: 400 });
    await database(
      "ad_rewards",
      { transaction_id: transaction, install_id: install, nonce },
      "resolution=ignore-duplicates,return=minimal",
    );
    return new Response("OK");
  } catch (error) {
    console.error(error);
    // A 5xx makes AdMob retry the callback later.
    return new Response("Try again.", { status: 500 });
  }
});

/** Google rotates its keys, so an unknown key ID refreshes them once. */
async function verified(query: string) {
  const keyId = new URLSearchParams(query).get("key_id");
  if (!keys.some((key) => String(key.keyId) === keyId)) {
    const response = await fetch(verifierKeysURL);
    if (!response.ok) throw new Error(`Google's verifier keys returned ${response.status}`);
    keys = (await response.json()).keys ?? [];
  }
  return verifyRewardCallback(query, keys);
}
