// Per-model pricing in USD per 1,000,000 tokens. The proxy bills by the model it
// ACTUALLY runs (env.UPSTREAM_MODEL in index.js), not the legacy name the app
// sends — so only the Gemini rows below are live. Gemini has no separate context-
// cache rate for our usage, so cache-hit == cache-miss == the flat input rate
// (costUSD treats absent cache fields as all-miss, which then prices correctly).
//
// Source: https://ai.google.dev/gemini-api/docs/pricing (verified 2026-06).
//   gemini-2.5-flash-lite : $0.10 in  / $0.40 out   ← current default (cheapest)
//   gemini-2.5-flash      : $0.30 in  / $2.50 out   ← optional higher-quality swap
//
// The DeepSeek rows are retained only so the legacy app-supplied model names stay
// in ALLOWED_MODELS history; they are never billed (we always price UPSTREAM_MODEL).

const PRICING = {
  "gemini-2.5-flash-lite": {
    inputCacheHitPerM: 0.10,
    inputCacheMissPerM: 0.10,
    outputPerM: 0.40,
  },
  "gemini-2.5-flash": {
    inputCacheHitPerM: 0.30,
    inputCacheMissPerM: 0.30,
    outputPerM: 2.50,
  },
  "deepseek-v4-pro": {
    inputCacheHitPerM: 0.003625, // 75% launch promo
    inputCacheMissPerM: 0.435,   // 75% launch promo
    outputPerM: 0.87,            // 75% launch promo
  },
  "deepseek-v4-flash": {
    inputCacheHitPerM: 0.0028,
    inputCacheMissPerM: 0.14,
    outputPerM: 0.28,
  },
};

export function isAllowedModel(model, allowedCsv) {
  const allowed = String(allowedCsv || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  return allowed.includes(model);
}

/**
 * True only if `model` has an EXPLICIT entry in PRICING (not the pro fallback).
 * index.js uses this as a loud guard: an ALLOWED model with no pricing row is a
 * config mistake. costUSD() still falls back to the pro rate so we never bill $0
 * (money leak), but that guessed rate could MIS-price a cheaper model — so the
 * request path refuses the call and logs loudly rather than billing on a guess.
 */
export function isPricedModel(model) {
  return Object.prototype.hasOwnProperty.call(PRICING, model);
}

/**
 * Real USD cost of one call given DeepSeek's `usage` block and the model used.
 * Mirrors DeepSeekUsage.costUSD(for:) in Swift: prefer the explicit cache
 * breakdown; if absent, treat all prompt tokens as the expensive cache-miss rate.
 */
export function costUSD(usage, model) {
  // Fall back to the conservative pro rate for an allowed-but-unpriced model,
  // mirroring estimateMaxCostUSD. Returning 0 here would book real spend as free
  // (a money leak) if a model is added to ALLOWED_MODELS but not to PRICING.
  const p = PRICING[model] || PRICING["deepseek-v4-pro"];
  const prompt = num(usage?.prompt_tokens);
  const completion = num(usage?.completion_tokens);
  const hit = Math.max(0, num(usage?.prompt_cache_hit_tokens));
  const missRaw = num(usage?.prompt_cache_miss_tokens);
  const miss = missRaw > 0 ? missRaw : Math.max(0, prompt - hit);

  const inputCost =
    (hit / 1_000_000) * p.inputCacheHitPerM +
    (miss / 1_000_000) * p.inputCacheMissPerM;
  const outputCost = (completion / 1_000_000) * p.outputPerM;
  return inputCost + outputCost;
}

/**
 * Conservative upper-bound cost for a request BEFORE we send it. Used to
 * "reserve" against the pot so concurrent in-flight calls can never overshoot.
 * Assumes the full max_tokens come back as output and the prompt is all
 * cache-miss, then clamps to a sane ceiling so one call can't reserve the world.
 */
export function estimateMaxCostUSD(model, maxTokens, approxPromptTokens) {
  const p = PRICING[model] || PRICING["deepseek-v4-pro"];
  const out = (num(maxTokens) / 1_000_000) * p.outputPerM;
  // Input must be a TRUE upper bound or the pot can be overshot at settle: the
  // caller estimates prompt tokens from byte length, but dense BPE content
  // (code, CJK, escaped JSON) tokenizes to MORE tokens than bytes/4. Apply a
  // safety multiplier so the reserved input >= the real billed input; settle
  // refunds the unused hold down to actual, so over-reserving is free of harm.
  const INPUT_SAFETY = 4; // undo the caller's /4 → reserve ~1 token per byte (no tokenizer exceeds this)
  const inp = (num(approxPromptTokens) * INPUT_SAFETY / 1_000_000) * p.inputCacheMissPerM;
  const est = out + inp;
  // Floor so tiny calls still reserve something. Ceiling is a backstop so one
  // call can't lock the whole pot; set above the real max for the default token
  // bounds (~$0.17 post-promo) so it never clamps below a call's true cost.
  return Math.min(1.00, Math.max(0.01, est));
}

function num(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}
