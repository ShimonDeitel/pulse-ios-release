// Minimal HS256 JWT for Pulse *session* tokens, built on Web Crypto (no deps).
//
// Flow: the app proves identity once with its Apple identity token (verified in
// apple.js), and we hand back one of these session tokens. The app then sends it
// as `Authorization: Bearer …` on every /v1/chat call. We pick the lifetime, so
// the app doesn't need a fresh Apple token per request.

const enc = new TextEncoder();
const dec = new TextDecoder();

export function b64urlEncode(bytes) {
  let bin = "";
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  for (let i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64urlDecodeToBytes(str) {
  const pad = str.length % 4 === 0 ? "" : "=".repeat(4 - (str.length % 4));
  const b64 = str.replace(/-/g, "+").replace(/_/g, "/") + pad;
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function b64urlJSON(obj) {
  return b64urlEncode(enc.encode(JSON.stringify(obj)));
}

async function hmacKey(secret) {
  return crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"]
  );
}

/** Mint a signed session token. `sub` is the stable Apple user id. */
export async function signSession(sub, secret, ttlSeconds, extra = {}) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "HS256", typ: "JWT" };
  const payload = {
    iss: "pulse-ai-proxy",
    sub,
    iat: now,
    exp: now + ttlSeconds,
    ...extra,
  };
  const signingInput = `${b64urlJSON(header)}.${b64urlJSON(payload)}`;
  const key = await hmacKey(secret);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(signingInput));
  return `${signingInput}.${b64urlEncode(sig)}`;
}

/**
 * Verify a session token. Returns the payload on success, or throws.
 * Uses Web Crypto's constant-time HMAC verify (no hand-rolled comparison).
 */
export async function verifySession(token, secret) {
  const parts = String(token || "").split(".");
  if (parts.length !== 3) throw new Error("malformed token");
  const [h, p, s] = parts;
  // Pin the algorithm. We only ever issue HS256; rejecting anything else stops an
  // attacker from swapping the header (e.g. to "none") to dodge signature checks.
  let header;
  try {
    header = JSON.parse(dec.decode(b64urlDecodeToBytes(h)));
  } catch {
    throw new Error("malformed header");
  }
  if (header.alg !== "HS256") throw new Error("unexpected alg");
  const key = await hmacKey(secret);
  const ok = await crypto.subtle.verify(
    "HMAC",
    key,
    b64urlDecodeToBytes(s),
    enc.encode(`${h}.${p}`)
  );
  if (!ok) throw new Error("bad signature");
  let payload;
  try {
    payload = JSON.parse(dec.decode(b64urlDecodeToBytes(p)));
  } catch {
    throw new Error("bad payload");
  }
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp === "number" && now >= payload.exp) {
    throw new Error("token expired");
  }
  if (!payload.sub) throw new Error("missing sub");
  return payload;
}

/** Decode a JWT's header + payload WITHOUT verifying. Used for Apple tokens to
 * read `kid`/`alg` before we know which key to verify with. */
export function decodeUnverified(token) {
  const parts = String(token || "").split(".");
  if (parts.length !== 3) throw new Error("malformed jwt");
  const header = JSON.parse(dec.decode(b64urlDecodeToBytes(parts[0])));
  const payload = JSON.parse(dec.decode(b64urlDecodeToBytes(parts[1])));
  return { header, payload, parts };
}
