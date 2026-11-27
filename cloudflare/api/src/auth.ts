import { HttpError } from "./http";

const JWT_TTL_SECONDS = 60 * 60 * 24 * 7; // 7 days

export interface AdminClaims {
  sub: string;
  role: "admin";
  iat: number;
  exp: number;
}

export function adminCorsHeaders(request: Request, allowedOrigins: string | undefined): Record<string, string> | null {
  const origin = request.headers.get("origin");
  if (!origin) return null;
  const list = (allowedOrigins ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  if (!list.includes(origin)) return null;
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "GET, POST, PATCH, PUT, DELETE, OPTIONS",
    "access-control-allow-headers": "authorization, content-type",
    "access-control-max-age": "86400",
    vary: "origin",
  };
}

export async function verifyPassword(password: string, storedHash: string): Promise<boolean> {
  const parts = storedHash.split("$");
  if (parts.length !== 4 || parts[0] !== "pbkdf2_sha256") return false;
  const iterations = Number(parts[1]);
  if (!Number.isInteger(iterations) || iterations < 10_000 || iterations > 500_000) return false;
  const salt = hexToBytes(parts[2]);
  const expected = hexToBytes(parts[3]);
  if (!salt || !expected || expected.length !== 32) return false;

  const baseKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const derivedBits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations },
    baseKey,
    256,
  );
  return constantTimeEqual(new Uint8Array(derivedBits), expected);
}

export async function signAdminToken(email: string, secret: string, ttlSeconds = JWT_TTL_SECONDS): Promise<{ token: string; expiresAt: number }> {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + ttlSeconds;
  const header = toBase64Url(new TextEncoder().encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const payload = toBase64Url(
    new TextEncoder().encode(JSON.stringify({ sub: email, role: "admin", iat: now, exp } satisfies AdminClaims)),
  );
  const key = await importHmacKey(secret, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${header}.${payload}`));
  return {
    token: `${header}.${payload}.${toBase64Url(new Uint8Array(sig))}`,
    expiresAt: exp,
  };
}

export async function requireAdmin(request: Request, secret: string | undefined): Promise<AdminClaims> {
  if (!secret) throw new HttpError("Admin auth is not configured.", 500);
  const auth = request.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) throw new HttpError("Missing admin session token.", 401);
  const token = auth.slice(7).trim();
  const parts = token.split(".");
  if (parts.length !== 3) throw new HttpError("Invalid admin session token.", 401);
  const [headerPart, payloadPart, sigPart] = parts;

  try {
    const key = await importHmacKey(secret, ["verify"]);
    const ok = await crypto.subtle.verify(
      "HMAC",
      key,
      fromBase64Url(sigPart),
      new TextEncoder().encode(`${headerPart}.${payloadPart}`),
    );
    if (!ok) throw new HttpError("Invalid or expired admin session.", 401);
    const header = JSON.parse(new TextDecoder().decode(fromBase64Url(headerPart))) as { alg?: string };
    if (header.alg !== "HS256") throw new HttpError("Invalid token algorithm.", 401);
    const claims = JSON.parse(new TextDecoder().decode(fromBase64Url(payloadPart))) as Partial<AdminClaims>;
    const now = Math.floor(Date.now() / 1000);
    if (typeof claims.exp !== "number" || claims.exp <= now) {
      throw new HttpError("Invalid or expired admin session.", 401);
    }
    if (claims.role !== "admin" || typeof claims.sub !== "string") {
      throw new HttpError("Not an admin.", 403);
    }
    return claims as AdminClaims;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError("Invalid or expired admin session.", 401);
  }
}

export async function constantTimeEmailEquals(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(a.trim().toLowerCase())),
    crypto.subtle.digest("SHA-256", enc.encode(b.trim().toLowerCase())),
  ]);
  return constantTimeEqual(new Uint8Array(ha), new Uint8Array(hb));
}

async function importHmacKey(secret: string, usages: ("sign" | "verify")[]): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    usages,
  );
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

function toBase64Url(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function fromBase64Url(text: string): Uint8Array {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (text.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

function hexToBytes(hex: string): Uint8Array | null {
  if (hex.length % 2 !== 0 || !/^[0-9a-f]+$/i.test(hex)) return null;
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}
