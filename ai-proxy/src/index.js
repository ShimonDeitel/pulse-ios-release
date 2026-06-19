import { Ledger } from "./ledger.js";
import { verifyAppleIdentityToken } from "./apple.js";
import { signSession, verifySession } from "./jwt.js";
import { costUSD, estimateMaxCostUSD, isAllowedModel, isPricedModel } from "./pricing.js";

export { Ledger };

// Gemini's OpenAI-compatible chat endpoint. The app speaks OpenAI format
// (messages, image_url base64 data URIs, tools, response_format) and Gemini's
// compat layer accepts it verbatim — so switching providers is a URL + key +
// model swap HERE, with NO app change: installed builds keep sending the legacy
// "deepseek-v4-flash" name, which we map onto the Gemini model below.
const GEMINI_CHAT_URL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";
// The single model every call actually runs on. Overridable via the
// UPSTREAM_MODEL var (swap to "gemini-2.5-flash" for higher quality at ~6× the
// output price) without a code edit. Must have a PRICING row in pricing.js.
const DEFAULT_UPSTREAM_MODEL = "gemini-2.5-flash-lite";
const SESSION_TTL_SECONDS = 60 * 24 * 60 * 60; // 60 days

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    try {
      if (request.method === "GET" && path === "/health") {
        return json(200, { ok: true, service: "pulse-ai-proxy", time: new Date().toISOString() });
      }
      if (request.method === "POST" && path === "/v1/session") {
        return await handleSession(request, env);
      }
      if (request.method === "POST" && path === "/v1/chat") {
        return await handleChat(request, env, ctx);
      }
      if (request.method === "GET" && path === "/v1/budget") {
        return await handleBudget(request, env);
      }
      if (path.startsWith("/admin/")) {
        return await handleAdmin(request, env, path);
      }
      return json(404, { error: "not found", code: "not_found" });
    } catch (err) {
      // Log the real cause server-side (visible in `wrangler tail`); never leak
      // internal exception text — or any of its structure — to the client.
      console.error("unhandled error:", err?.stack || err);
      return json(500, { error: "internal error", code: "internal" });
    }
  },
};

// ── Helpers ──────────────────────────────────────────────────────────────────

function json(status, obj, extraHeaders = {}) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      // Hardening defaults on every response. nosniff stops content-type games;
      // no-store keeps budget/cost figures out of any intermediary cache;
      // no-referrer avoids leaking the request path. extraHeaders still augments.
      "content-type": "application/json",
      "x-content-type-options": "nosniff",
      "cache-control": "no-store",
      "referrer-policy": "no-referrer",
      ...extraHeaders,
    },
  });
}

function bearer(request) {
  const h = request.headers.get("authorization") || "";
  const m = h.match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : null;
}

// Reject a body before parsing if its declared size blows past `limit`. The
// post-parse byte check still enforces the exact prompt budget, but parsing a
// multi-MB JSON blob first is itself a CPU/memory DoS vector — stop it at the door.
function tooLargeByHeader(request, limit) {
  const cl = Number(request.headers.get("content-length") || 0);
  return Number.isFinite(cl) && cl > limit;
}

// Constant-time equality for secrets. A plain `a !== b` short-circuits on the
// first differing byte, leaking the secret's length and prefix through response
// timing. HMAC both sides under a per-call random key and compare fixed-length
// digests, so neither length nor content is observable via timing.
async function safeEqual(a, b) {
  const e = new TextEncoder();
  const key = await crypto.subtle.generateKey({ name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const da = new Uint8Array(await crypto.subtle.sign("HMAC", key, e.encode(String(a ?? ""))));
  const db = new Uint8Array(await crypto.subtle.sign("HMAC", key, e.encode(String(b ?? ""))));
  let diff = 0;
  for (let i = 0; i < da.length; i++) diff |= da[i] ^ db[i];
  return diff === 0;
}

function utcMonth() {
  const d = new Date();
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  return `${d.getUTCFullYear()}-${mm}`;
}

// Daily pacing: a user's monthly allowance unlocks evenly across the month and
// carries forward. This is the fraction unlocked SO FAR — day-of-month divided by
// days-in-month — so it's 1/30 on day 1 and exactly 1.0 on the last day (every
// month reaches the full cap, regardless of length). accruedCap = cap × this.
function utcMonthFractionElapsed() {
  const d = new Date();
  const day = d.getUTCDate();
  const daysInMonth = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
  return Math.min(1, Math.max(0, day / daysInMonth));
}

function ledgerStub(env) {
  return env.LEDGER.get(env.LEDGER.idFromName("global"));
}

// Gemini's free tier is a low per-minute request quota, and a 429 typically
// clears within a few seconds ("retry in 7.9s"). Rather than fail the user on a
// brief spike, wait out a SHORT retry-after once and try again. Deep exhaustion
// (long retry-after) is surfaced as 429 immediately so the app shows its usual
// "usage limit" message. One retry max — keeps worker wall-clock bounded.
const GEMINI_MAX_RETRY_WAIT_MS = 9000;

function parseRetryAfterMs(header, body) {
  const h = Number(header);                       // standard Retry-After: seconds
  if (Number.isFinite(h) && h > 0) return h * 1000;
  const s = String(body || "");                   // Gemini body: "retry in 7.9s" / "retryDelay":"7s"
  const m = s.match(/retry in ([\d.]+)s/i) || s.match(/"retryDelay":\s*"([\d.]+)s"/i);
  if (m) { const n = parseFloat(m[1]); if (Number.isFinite(n)) return n * 1000; }
  return 0;
}

async function geminiFetch(body, env) {
  const init = {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${env.GEMINI_API_KEY}` },
    body: JSON.stringify(body),
  };
  let res = await fetch(GEMINI_CHAT_URL, init);
  if (res.status === 429) {
    const peek = await res.clone().text().catch(() => "");
    const waitMs = parseRetryAfterMs(res.headers.get("retry-after"), peek);
    if (waitMs > 0 && waitMs <= GEMINI_MAX_RETRY_WAIT_MS) {
      await new Promise((r) => setTimeout(r, waitMs + 400));
      res = await fetch(GEMINI_CHAT_URL, init);
    }
  }
  return res;
}

// ── Free-tier provider waterfall ──────────────────────────────────────────────
// Free users NEVER touch the paid Gemini pot. Instead we cascade across 100%-free
// OpenAI-compatible endpoints (AI Studio free tier, Cerebras, OpenRouter ":free").
// Each key is an OPTIONAL Worker secret — a provider with no key is skipped, so you
// can add them one at a time:
//   wrangler secret put AISTUDIO_FREE_KEY
//   wrangler secret put CEREBRAS_FREE_KEY
//   wrangler secret put OPENROUTER_FREE_KEY
// With ZERO free keys configured, freeChat() returns null and the caller falls back
// to the paid pot — so the app keeps working until you wire the free keys.
function freeProviders(env) {
  const p = [];
  if (env.AISTUDIO_FREE_KEY)  p.push({ name: "ai-studio",  url: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", key: env.AISTUDIO_FREE_KEY,  model: env.FREE_MODEL_AISTUDIO  || "gemini-2.5-flash-lite" });
  if (env.CEREBRAS_FREE_KEY)  p.push({ name: "cerebras",   url: "https://api.cerebras.ai/v1/chat/completions",                               key: env.CEREBRAS_FREE_KEY,  model: env.FREE_MODEL_CEREBRAS  || "gpt-oss-120b" });
  if (env.OPENROUTER_FREE_KEY) p.push({ name: "openrouter", url: "https://openrouter.ai/api/v1/chat/completions",                            key: env.OPENROUTER_FREE_KEY, model: env.FREE_MODEL_OPENROUTER || "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free" });
  return p;
}

// Returns a Response on success / all-busy, or null when NO free providers are
// configured. The caller treats null as "free AI unavailable" (429 free_busy) —
// free traffic NEVER falls through to the paid pot under any circumstances.
async function freeChat(body, env) {
  const providers = freeProviders(env);
  if (providers.length === 0) return null;
  for (const prov of providers) {
    try {
      const res = await fetch(prov.url, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${prov.key}` },
        // Forward only the safe, already-bounded fields — never our routing hint.
        // temperature + response_format are passed through so free-user JSON plan
        // generation keeps working; tools are intentionally omitted (not all free
        // models support them — they degrade to plain text rather than erroring).
        body: JSON.stringify({
          messages: body.messages,
          model: prov.model,
          // Free tiers commonly reject large completion budgets with a 400 —
          // clamp well inside every provider's free limit.
          max_tokens: Math.min(Number(body.max_tokens) || 4096, 4096),
          temperature: body.temperature,
          ...(body.response_format ? { response_format: body.response_format } : {}),
          stream: false,
        }),
      });
      if (!res.ok) {
        // Log WHY the provider refused (status alone hid the real cause).
        const errBody = await res.text().catch(() => "");
        console.warn(`free[${prov.name}] -> ${res.status}: ${errBody.slice(0, 300)}`);
        continue;
      }
      const text = await res.text();
      let parsed;
      try { parsed = JSON.parse(text); } catch { continue; }
      const content = parsed?.choices?.[0]?.message?.content;
      if (!content) continue;
      // Free models cost us nothing → no ledger, cost 0.
      return json(200, parsed, { "x-pulse-free-provider": prov.name, "x-pulse-cost-usd": "0.000000" });
    } catch (e) {
      console.warn(`free[${prov.name}] threw: ${e?.message || e}`);
      continue;
    }
  }
  // Every free provider was rate-limited or down → the "too many users" signal the
  // app turns into "try again later — or upgrade to Pro for Primary Access".
  return json(429, { error: "Free AI is busy right now.", code: "free_busy" }, { "retry-after": "30" });
}

async function requireSession(request, env) {
  if (!env.SESSION_SIGNING_SECRET) throw httpError(500, "server misconfigured", "internal");
  const token = bearer(request);
  if (!token) throw httpError(401, "missing session token", "unauthorized");
  try {
    return await verifySession(token, env.SESSION_SIGNING_SECRET);
  } catch {
    throw httpError(401, "invalid or expired session", "unauthorized");
  }
}

function httpError(status, message, code) {
  const e = new Error(message);
  e.status = status;
  e.code = code;
  return e;
}

function asErrorResponse(err) {
  if (err && err.status) return json(err.status, { error: err.message, code: err.code || "error" });
  console.error("asErrorResponse:", err?.stack || err);
  return json(500, { error: "internal error", code: "internal" });
}

// ── /v1/session : exchange a fresh Apple identity token for a Pulse session ───

async function handleSession(request, env) {
  if (!env.SESSION_SIGNING_SECRET) return json(500, { error: "server misconfigured", code: "internal" });
  if (tooLargeByHeader(request, 65536)) return json(413, { error: "request payload too large", code: "payload_too_large" });
  let body;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "invalid JSON body", code: "bad_request" });
  }

  // ── Anonymous / device free-tier session (Android, or any client without Sign
  //    in with Apple). Issues a session JWT pinned to tier:"anon" that can NEVER
  //    draw from the paid pot (enforced by the guard in handleChat). Rate-limited
  //    per client IP so a bot cannot mint unlimited sessions and burn the shared
  //    free-provider keys. Disabled unless ANON_SESSIONS_ENABLED === "1", in which
  //    case the branch is invisible (returns the generic 404).
  if (body?.anonymous === true || body?.mode === "anonymous") {
    if (String(env.ANON_SESSIONS_ENABLED || "") !== "1") {
      return json(404, { error: "not found", code: "not_found" });
    }
    const clientIp = request.headers.get("cf-connecting-ip")
      || request.headers.get("x-forwarded-for") || "unknown";
    const deviceId = typeof body?.deviceId === "string" ? body.deviceId.slice(0, 128) : "";
    const perHour = Number(env.ANON_ISSUE_PER_HOUR_PER_IP) || 5;
    const gate = await ledgerStub(env).anonIssueAllowed({ key: `anon-issue:${clientIp}`, perHour });
    if (!gate.allowed) {
      return json(429, { error: "too many anonymous sessions", code: "rate_limited" },
        { "retry-after": String(gate.retryAfterSeconds || 3600) });
    }
    // Prefer the client device id so the per-device rate limit binds to a device
    // rather than a fresh random subject every mint; else fall back to random.
    const sub = deviceId ? `anon:dev:${deviceId}` : `anon:${crypto.randomUUID()}`;
    const ttl = Number(env.ANON_SESSION_TTL_SECONDS) || (30 * 24 * 60 * 60);
    const sessionToken = await signSession(sub, env.SESSION_SIGNING_SECRET, ttl, { tier: "anon" });
    const expiresAt = new Date(Date.now() + ttl * 1000).toISOString();
    return json(200, { sessionToken, expiresAt, tier: "anon" });
  }

  const identityToken = body?.identityToken;
  if (!identityToken) return json(400, { error: "identityToken required", code: "bad_request" });

  let payload;
  try {
    payload = await verifyAppleIdentityToken(identityToken, env.APPLE_BUNDLE_ID);
  } catch (e) {
    // The exact reason (bad sig / wrong aud / expired) is a hint to an attacker —
    // log it, return an opaque 401.
    console.error("apple verify failed:", e?.message || e);
    return json(401, { error: "apple verification failed", code: "unauthorized" });
  }
  const sessionToken = await signSession(payload.sub, env.SESSION_SIGNING_SECRET, SESSION_TTL_SECONDS);
  const expiresAt = new Date(Date.now() + SESSION_TTL_SECONDS * 1000).toISOString();
  return json(200, { sessionToken, expiresAt });
}

// ── /v1/chat : the metered Gemini proxy ───────────────────────────────────────

async function handleChat(request, env, ctx) {
  // NOTE: the GEMINI_API_KEY check lives below, gated to the PAID path only.
  // Free / anonymous (Android) traffic must never be blocked by a missing paid
  // key — it only ever hits the zero-cost free providers.
  let session;
  try {
    session = await requireSession(request, env);
  } catch (e) {
    return asErrorResponse(e);
  }
  const userId = session.sub;
  const month = utcMonth();
  const cap = Number(env.PER_USER_CAP_USD) || 0;

  // Reject oversized bodies before parsing. The post-parse byte check below still
  // enforces the exact prompt budget; this is the cheap early door-guard.
  const hardBodyLimit = (Number(env.MAX_PROMPT_BYTES) || 262144) + 65536;
  if (tooLargeByHeader(request, hardBodyLimit)) {
    return json(413, { error: "request payload too large", code: "payload_too_large" });
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "invalid JSON body", code: "bad_request" });
  }

  const model = body?.model;
  if (!isAllowedModel(model, env.ALLOWED_MODELS)) {
    // Don't reflect the client-supplied value back — it could be an unbounded or
    // hostile string. The client already knows which model it requested.
    return json(400, { error: "model not allowed", code: "bad_request" });
  }
  // Every call runs on ONE Gemini model regardless of what the client asked for.
  // Installed app builds still send the legacy "deepseek-v4-flash" name (accepted
  // via ALLOWED_MODELS above); we map it onto the real upstream model here so old
  // binaries keep working with zero app changes. We forward AND price by this
  // model, never the requested one.
  const upstreamModel = String(env.UPSTREAM_MODEL || DEFAULT_UPSTREAM_MODEL).trim();
  // Loud guard: the upstream model MUST have an explicit PRICING row. costUSD()/
  // estimateMaxCostUSD() fall back to a conservative rate so we never bill $0 (a
  // money leak), but that guessed rate could MIS-price the model — so fail CLOSED
  // here and make the misconfiguration impossible to miss in logs.
  if (!isPricedModel(upstreamModel)) {
    console.error(
      `[pricing] FATAL config: UPSTREAM_MODEL "${upstreamModel}" has no PRICING entry — ` +
      `refusing to bill at a guessed rate. Add it to PRICING in src/pricing.js.`
    );
    return json(503, { error: "model temporarily unavailable", code: "model_misconfigured" });
  }

  // Bound the INPUT before we do anything else. max_tokens only caps OUTPUT cost;
  // a giant prompt is billed as (expensive) cache-miss input, so an unbounded
  // payload is a cost-amplification vector. Reject oversized/malformed message
  // arrays outright — this also stops a junk body from ever reaching DeepSeek.
  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    return json(400, { error: "messages must be a non-empty array", code: "bad_request" });
  }
  const maxMessages = Number(env.MAX_MESSAGES) || 200;
  if (body.messages.length > maxMessages) {
    return json(400, { error: `too many messages (max ${maxMessages})`, code: "payload_too_large" });
  }
  const messagesJson = JSON.stringify(body.messages);
  const maxPromptBytes = Number(env.MAX_PROMPT_BYTES) || 262144; // 256 KB
  if (messagesJson.length > maxPromptBytes) {
    return json(413, { error: "request payload too large", code: "payload_too_large" });
  }

  // Clamp output tokens server-side to bound per-call cost no matter what's asked.
  const maxClamp = Number(env.MAX_OUTPUT_TOKENS) || 16384;
  body.max_tokens = Math.max(64, Math.min(Number(body.max_tokens) || maxClamp, maxClamp));
  // We MUST see token usage to meter, so streaming is disabled at the proxy.
  body.stream = false;

  // ── Tier split ────────────────────────────────────────────────────────────
  // Free users route to the free-provider waterfall and NEVER draw down the paid
  // pot. Pro users — and legacy app builds that send no `tier` — get Primary
  // Access to the metered paid model below. A free waterfall miss returns 429
  // free_busy → the app shows "too many users — try again, or upgrade for
  // Primary Access". (Input was already size/clamp-bounded above, so free
  // requests are bounded too.)
  // Tier comes from a HEADER (X-Pulse-Tier), never the body — so it can never
  // leak into the upstream model payload, and old app builds (no header) default
  // to the paid path. Free → free-provider waterfall; pro/legacy → metered paid.
  // A session minted as tier:"anon" (Android/device path) can NEVER reach the
  // paid pot, no matter what X-Pulse-Tier the client sends — the SIGNED JWT claim
  // wins over the (advisory) header. Apple sessions (no tier claim, or "pro")
  // honour the header. Because `session` came from verifySession (HMAC-checked),
  // `session.tier` is not client-forgeable.
  const headerTier = request.headers.get("x-pulse-tier");
  const tier = session.tier === "anon" ? "free" : headerTier;
  if (tier === "free") {
    const freeRes = await freeChat(body, env);
    if (freeRes) return freeRes;
    // HARD WALL: free users NEVER draw from the paid pot — not even when no
    // free keys are configured yet. In that state free AI is simply busy; the
    // app shows "too many people are using Pulse" with the Upgrade button.
    return json(429, { error: "Free AI is busy right now.", code: "free_busy" }, { "retry-after": "60" });
  }

  // PAID path only past here. The Gemini key is required to serve it; free/anon
  // already returned above, so a missing paid key never blocks free users.
  if (!env.GEMINI_API_KEY) return json(500, { error: "server misconfigured: no Gemini key", code: "internal" });

  const approxPromptTokens = Math.ceil(messagesJson.length / 4);
  const estMaxCost = estimateMaxCostUSD(upstreamModel, body.max_tokens, approxPromptTokens);

  // Daily pacing ceiling: how much of the monthly cap has unlocked so far.
  const accruedCap = cap * utcMonthFractionElapsed();

  const ledger = ledgerStub(env);
  const pre = await ledger.preflight({
    userId, month, perUserCapUSD: cap, accruedCapUSD: accruedCap, estMaxCostUSD: estMaxCost,
    rateLimitPerMin: Number(env.RATE_LIMIT_PER_MIN) || 30,
    dailyCapUSD: Number(env.DAILY_CAP_USD) || 0,
  });
  if (!pre.allowed) {
    if (pre.reason === "disabled") {
      // Admin kill switch is engaged — AI is paused for everyone. Reuse the 402
      // path so the app shows its existing "Pulse AI is taking a break" message
      // (no app change needed).
      return json(402, { error: "AI is paused", code: "disabled" });
    }
    if (pre.reason === "daily_pot_cap") {
      // The hard daily global ceiling is hit — comes back tomorrow. 429 maps to
      // the app's existing "usage limit, resets tomorrow" copy (no app change).
      return json(429, { error: "daily limit reached", code: "daily_pot_cap" });
    }
    if (pre.reason === "rate_limited") {
      // Too many requests in the last minute — purely a volume guard, not a money
      // wall. 429 with Retry-After so a well-behaved client backs off.
      return json(429, {
        error: "too many requests", code: "rate_limited",
      }, { "retry-after": String(Math.ceil((pre.retryAfterMs || 60000) / 1000)) });
    }
    if (pre.reason === "user_cap") {
      // Whole month's $2.75 is spent → "monthly limit" modal in the app.
      return json(429, {
        error: "monthly AI limit reached", code: "user_cap",
        userRemaining: 0, perUserCapUSD: cap,
      });
    }
    if (pre.reason === "daily_cap") {
      // Today's paced slice is spent but the month isn't → soft "resets tomorrow".
      return json(429, {
        error: "daily AI limit reached", code: "daily_cap",
        userAvailableNow: 0, userRemaining: pre.userRemaining, perUserCapUSD: cap,
      });
    }
    return json(402, {
      error: "AI temporarily unavailable", code: "pot_exhausted",
      potRemaining: pre.potRemaining,
    });
  }

  let settled = false;
  let billedCost = 0; // real cost once a 2xx response is priced; used by the fallback
  const reservationId = pre.reservationId;
  try {
    // Forward to Gemini. Pin the model to the one we meter by — the client's
    // requested name is a legacy alias we deliberately ignore for the call.
    // geminiFetch waits out a SHORT free-tier 429 once before giving up.
    body.model = upstreamModel;
    const dsRes = await geminiFetch(body, env);

    const text = await dsRes.text();
    if (!dsRes.ok) {
      // Gemini itself errored (e.g. 400 bad model/request, 429 rate, 5xx). Release
      // the hold. Do NOT forward the raw body — it can carry upstream internals.
      // Log it server-side and return an opaque error, preserving the status so the
      // app's existing 429/5xx handling still works.
      await ledger.settle({ reservationId, userId, month, actualCostUSD: 0, perUserCapUSD: cap });
      settled = true;
      console.error(`gemini upstream ${dsRes.status}:`, text.slice(0, 500));
      const status = dsRes.status >= 500 ? 502 : dsRes.status;
      return json(status, { error: "AI provider error", code: "upstream" });
    }

    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch {
      await ledger.settle({ reservationId, userId, month, actualCostUSD: 0, perUserCapUSD: cap });
      settled = true;
      return json(502, { error: "bad upstream response", code: "upstream" });
    }

    const cost = costUSD(parsed.usage, upstreamModel);
    billedCost = cost; // remember the real cost so the fallback can't lose it as $0
    const snap = await ledger.settle({ reservationId, userId, month, actualCostUSD: cost, perUserCapUSD: cap });
    settled = true;

    return json(200, parsed, {
      "x-pulse-cost-usd": cost.toFixed(6),
      "x-pulse-user-remaining-usd": snap.userRemaining.toFixed(6),
      "x-pulse-pot-remaining-usd": snap.potRemaining.toFixed(6),
    });
  } catch (err) {
    console.error("upstream request failed:", err?.message || err);
    return json(502, { error: "upstream request failed", code: "upstream" });
  } finally {
    if (!settled) {
      // The primary settle never completed. Reconcile to the BEST-KNOWN cost:
      //   • billedCost > 0  → a 2xx response was priced but settle/return threw;
      //     book the real spend so a billed call isn't recorded as free.
      //   • billedCost == 0 → failed before/at the call; release the hold.
      // bookIfMissing:false makes this a no-op if the primary settle actually
      // applied (reservation row already gone), so we never double-charge.
      ctx.waitUntil(
        ledger.settle({
          reservationId, userId, month,
          actualCostUSD: billedCost, perUserCapUSD: cap, bookIfMissing: false,
        }).catch(() => {})
      );
    }
  }
}

// ── /v1/budget : the app's real remaining-budget meter ───────────────────────

async function handleBudget(request, env) {
  let session;
  try {
    session = await requireSession(request, env);
  } catch (e) {
    return asErrorResponse(e);
  }
  const cap = Number(env.PER_USER_CAP_USD) || 0;
  const accruedCap = cap * utcMonthFractionElapsed();
  const snap = await ledgerStub(env).usage({
    userId: session.sub, month: utcMonth(), perUserCapUSD: cap, accruedCapUSD: accruedCap,
  });
  return json(200, {
    perUserCapUSD: cap,
    userSpentUSD: snap.userSpent,
    userRemainingUSD: snap.userRemaining,
    userAvailableNowUSD: snap.userAvailableNow,
    potRemainingUSD: snap.potRemaining,
    month: utcMonth(),
  });
}

// ── /admin : top up the pot, check status (protected by ADMIN_SECRET) ────────

async function handleAdmin(request, env, path) {
  if (!env.ADMIN_SECRET) return json(500, { error: "admin not configured", code: "internal" });
  if (tooLargeByHeader(request, 65536)) return json(413, { error: "request payload too large", code: "payload_too_large" });
  const provided = bearer(request) || request.headers.get("x-admin-secret");
  // Constant-time compare so the admin secret can't be recovered byte-by-byte via
  // response-timing analysis.
  if (!(await safeEqual(provided, env.ADMIN_SECRET))) {
    return json(401, { error: "unauthorized", code: "unauthorized" });
  }

  const ledger = ledgerStub(env);
  if (path === "/admin/status" && request.method === "GET") {
    return json(200, await ledger.status());
  }
  if (path === "/admin/topup" && request.method === "POST") {
    let body;
    try {
      body = await request.json();
    } catch {
      return json(400, { error: "invalid JSON body", code: "bad_request" });
    }
    const amountUSD = Number(body?.amountUSD);
    if (!Number.isFinite(amountUSD) || amountUSD <= 0) {
      return json(400, { error: "amountUSD must be a positive number", code: "bad_request" });
    }
    return json(200, await ledger.topup({ amountUSD }));
  }
  // Kill switch — pause/resume all AI instantly (no redeploy).
  if (path === "/admin/pause" && request.method === "POST") {
    return json(200, await ledger.setEnabled({ enabled: false }));
  }
  if (path === "/admin/resume" && request.method === "POST") {
    return json(200, await ledger.setEnabled({ enabled: true }));
  }
  // Set the absolute pot ceiling directly (lower it to tighten max spend).
  if (path === "/admin/setcap" && request.method === "POST") {
    let body;
    try {
      body = await request.json();
    } catch {
      return json(400, { error: "invalid JSON body", code: "bad_request" });
    }
    const totalUSD = Number(body?.totalUSD);
    if (!Number.isFinite(totalUSD) || totalUSD < 0) {
      return json(400, { error: "totalUSD must be a non-negative number", code: "bad_request" });
    }
    return json(200, await ledger.setCap({ totalUSD }));
  }
  return json(405, { error: "method not allowed", code: "method_not_allowed" });
}
