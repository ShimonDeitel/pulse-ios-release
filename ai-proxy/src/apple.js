// Verify a "Sign in with Apple" identity token (a JWT signed by Apple, RS256).
// We check the signature against Apple's published keys and validate the claims.
// On success the app is who it says it is, and `sub` is the stable user id we
// meter against — the same value as `credential.user` in the iOS app.

import { decodeUnverified, b64urlDecodeToBytes } from "./jwt.js";

const APPLE_ISS = "https://appleid.apple.com";
const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";

// Module-scope cache. A Worker isolate is reused across requests, so we avoid
// re-fetching Apple's keys on every sign-in. Apple rotates keys infrequently.
let jwksCache = { keys: null, fetchedAt: 0 };
const JWKS_TTL_MS = 6 * 60 * 60 * 1000; // 6 hours

async function getAppleKeys() {
  const now = Date.now();
  if (jwksCache.keys && now - jwksCache.fetchedAt < JWKS_TTL_MS) {
    return jwksCache.keys;
  }
  const res = await fetch(APPLE_JWKS_URL, { cf: { cacheTtl: 3600 } });
  if (!res.ok) {
    if (jwksCache.keys) return jwksCache.keys; // serve stale rather than fail
    throw new Error(`apple jwks fetch failed: ${res.status}`);
  }
  const data = await res.json();
  jwksCache = { keys: data.keys || [], fetchedAt: now };
  return jwksCache.keys;
}

async function importApplePublicKey(jwk) {
  return crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: jwk.alg, use: jwk.use, ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );
}

/**
 * Verify the token and return its payload, or throw. `expectedAud` MUST be the
 * app's bundle id — this is what stops a token minted for some OTHER app from
 * being accepted here.
 */
export async function verifyAppleIdentityToken(token, expectedAud) {
  const { header, payload, parts } = decodeUnverified(token);
  if (header.alg !== "RS256") throw new Error("unexpected alg");

  const keys = await getAppleKeys();
  const jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) throw new Error("no matching apple key");

  const key = await importApplePublicKey(jwk);
  const enc = new TextEncoder();
  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    b64urlDecodeToBytes(parts[2]),
    enc.encode(`${parts[0]}.${parts[1]}`)
  );
  if (!ok) throw new Error("bad apple signature");

  // Claim validation.
  if (payload.iss !== APPLE_ISS) throw new Error("bad iss");
  const audOk = Array.isArray(payload.aud)
    ? payload.aud.includes(expectedAud)
    : payload.aud === expectedAud;
  if (!audOk) throw new Error("bad aud");
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp === "number" && now >= payload.exp) {
    throw new Error("apple token expired");
  }
  if (!payload.sub) throw new Error("missing sub");

  return payload;
}
