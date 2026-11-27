// Checks AdMob's server-side verification (SSV) callbacks: https://developers.google.com/admob/ios/ssv
export const verifierKeysURL = "https://www.gstatic.com/admob/reward/verifier-keys.json";

export interface AdMobKey {
  keyId: number | string;
  base64: string;
}

export async function verifyRewardCallback(query: string, keys: AdMobKey[]): Promise<boolean> {
  const at = query.indexOf("&signature=");
  if (at < 0) return false;
  const params = new URLSearchParams(query);
  const signature = params.get("signature");
  const key = keys.find((k) => String(k.keyId) === params.get("key_id"));
  if (!signature || !key) return false;
  const raw = derToRaw(fromBase64(signature));
  if (!raw) return false;
  const publicKey = await crypto.subtle.importKey(
    "spki",
    fromBase64(key.base64),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  return crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    raw,
    new TextEncoder().encode(query.slice(0, at)),
  );
}

function fromBase64(text: string): Uint8Array {
  const plain = text.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(plain + "=".repeat((4 - (plain.length % 4)) % 4)), (c) => c.charCodeAt(0));
}

function derToRaw(der: Uint8Array): Uint8Array | null {
  if (der[0] !== 0x30) return null;
  let offset = 2;
  const halves: Uint8Array[] = [];
  for (let i = 0; i < 2; i++) {
    if (der[offset] !== 0x02) return null;
    const length = der[offset + 1];
    let bytes = der.slice(offset + 2, offset + 2 + length);
    while (bytes.length > 32 && bytes[0] === 0) bytes = bytes.slice(1);
    if (bytes.length > 32) return null;
    const half = new Uint8Array(32);
    half.set(bytes, 32 - bytes.length);
    halves.push(half);
    offset += 2 + length;
  }
  const raw = new Uint8Array(64);
  raw.set(halves[0]);
  raw.set(halves[1], 32);
  return raw;
}
