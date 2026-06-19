// Standalone validation harness for the Ledger Durable Object.
//
// The Worker doesn't compile into the iOS app, so our "build + verify" for
// server code is: `node --check` every src file (syntax) + this harness
// (behavior). It loads the REAL src/ledger.js by shimming the two runtime
// dependencies it needs — the `cloudflare:workers` DurableObject base class
// and `ctx.storage.sql` — with a node:sqlite-backed fake whose .exec(q,...p)
// .toArray() shape matches the Cloudflare SQL API exactly.
//
// Run: node test/ledger.harness.mjs   (Node 22+, for node:sqlite)

import { DatabaseSync } from "node:sqlite";
import { readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const LEDGER_SRC = join(__dirname, "..", "src", "ledger.js");
const INDEX_SRC = join(__dirname, "..", "src", "index.js");
const JWT_SRC = join(__dirname, "..", "src", "jwt.js");

// ── Load the real Ledger with the cloudflare:workers import shimmed out ──────
function loadLedgerClass() {
  let src = readFileSync(LEDGER_SRC, "utf8");
  const shim = `class DurableObject {
  constructor(ctx, env) { this.ctx = ctx; this.env = env; }
}\n`;
  // Replace the single runtime import with a local base class definition.
  const replaced = src.replace(
    /import\s*\{\s*DurableObject\s*\}\s*from\s*["']cloudflare:workers["'];?/,
    shim
  );
  if (replaced === src) throw new Error("could not find cloudflare:workers import to shim");
  const genPath = join(tmpdir(), `ledger.gen.${process.pid}.mjs`);
  writeFileSync(genPath, replaced);
  return { genPath, url: pathToFileURL(genPath).href };
}

// ── Fake ctx whose storage.sql mirrors the Cloudflare DO SQL surface ─────────
function makeCtx(env) {
  const db = new DatabaseSync(":memory:");
  const sql = {
    exec(query, ...params) {
      if (/^\s*SELECT/i.test(query)) {
        const rows = db.prepare(query).all(...params);
        return { toArray: () => rows };
      }
      db.prepare(query).run(...params);
      return { toArray: () => [] };
    },
  };
  return {
    storage: { sql },
    blockConcurrencyWhile: (fn) => { fn(); }, // #init is synchronous
    _db: db,
  };
}

// ── Tiny assert kit ──────────────────────────────────────────────────────────
let passed = 0;
const failures = [];
function ok(cond, msg) { if (cond) { passed++; } else { failures.push(msg); console.error("  ✗ " + msg); } }
function approx(a, b, eps, msg) { ok(Math.abs(a - b) <= (eps ?? 1e-9), `${msg} (got ${a}, want ~${b})`); }

const UTC_MONTH = (() => {
  const d = new Date();
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
})();

async function main() {
  const { genPath, url } = loadLedgerClass();
  let Ledger;
  try {
    ({ Ledger } = await import(url));
  } finally {
    // generated shim lives in the OS temp dir; remove it once imported
    try { rmSync(genPath); } catch {}
  }

  const CAP = 2.75; // monthly per-user cap

  // ── Test 1: mid-month, fresh user — a small call is allowed ────────────────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    const accrued = CAP * (10 / 30); // simulate day 10 of a 30-day month ≈ 0.9167
    const pre = await led.preflight({
      userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP,
      accruedCapUSD: accrued, estMaxCostUSD: 0.10,
    });
    ok(pre.allowed === true, "T1: mid-month small call allowed");
    ok(typeof pre.reservationId === "string" && pre.reservationId.length > 0, "T1: reservationId minted");
    approx(pre.userAvailableNow, accrued, 1e-6, "T1: userAvailableNow == accrued for fresh user");
    approx(pre.userRemaining, CAP, 1e-9, "T1: userRemaining == full cap for fresh user");
    approx(pre.potSpent, 0.10, 1e-9, "T1: pot holds the reserved max");
  }

  // ── Test 2: daily_cap — today's slice spent, month is NOT ──────────────────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    const accrued = CAP * (10 / 30); // ≈ 0.9167
    // Book ~today's whole slice via a direct settle (no reservation).
    await led.settle({ userId: "u1", month: UTC_MONTH, actualCostUSD: 0.92, perUserCapUSD: CAP });
    const pre = await led.preflight({
      userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP,
      accruedCapUSD: accrued, estMaxCostUSD: 0.05,
    });
    ok(pre.allowed === false, "T2: blocked once today's slice is spent");
    ok(pre.reason === "daily_cap", `T2: reason is daily_cap (got ${pre.reason})`);
    ok(pre.userRemaining > 0, "T2: month is NOT exhausted (userRemaining > 0)");
    ok(pre.userAvailableNow <= 0, "T2: userAvailableNow clamped to 0");
  }

  // ── Test 3: user_cap precedence — whole month spent (even on last day) ─────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    const accruedFull = CAP * (30 / 30); // last day: full cap unlocked
    await led.settle({ userId: "u1", month: UTC_MONTH, actualCostUSD: CAP, perUserCapUSD: CAP });
    const pre = await led.preflight({
      userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP,
      accruedCapUSD: accruedFull, estMaxCostUSD: 0.05,
    });
    ok(pre.allowed === false, "T3: blocked when month fully spent");
    ok(pre.reason === "user_cap", `T3: user_cap wins over daily_cap (got ${pre.reason})`);
    approx(pre.userRemaining, 0, 1e-9, "T3: userRemaining == 0");
  }

  // ── Test 4: pot_exhausted — global pot can't cover the reservation ─────────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 0.05 }), { POT_TOTAL_USD: 0.05 });
    const pre = await led.preflight({
      userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP,
      accruedCapUSD: CAP, estMaxCostUSD: 0.10, // 0.10 > 0.05 pot
    });
    ok(pre.allowed === false, "T4: blocked when pot can't cover reservation");
    ok(pre.reason === "pot_exhausted", `T4: reason is pot_exhausted (got ${pre.reason})`);
  }

  // ── Test 5: reserve→settle refunds the unused hold ─────────────────────────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    const pre = await led.preflight({
      userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP,
      accruedCapUSD: CAP, estMaxCostUSD: 0.50,
    });
    approx(pre.potSpent, 0.50, 1e-9, "T5: pot reserved at max (0.50)");
    const snap = await led.settle({
      reservationId: pre.reservationId, userId: "u1", month: UTC_MONTH,
      actualCostUSD: 0.05, perUserCapUSD: CAP,
    });
    approx(snap.potSpent, 0.05, 1e-9, "T5: pot settled to actual (0.05) — 0.45 refunded");
    approx(snap.userSpent, 0.05, 1e-9, "T5: user charged actual (0.05)");
  }

  // ── Test 6: settle(0) releases the hold entirely (failed upstream call) ─────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    const pre = await led.preflight({
      userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP,
      accruedCapUSD: CAP, estMaxCostUSD: 0.50,
    });
    const snap = await led.settle({
      reservationId: pre.reservationId, userId: "u1", month: UTC_MONTH,
      actualCostUSD: 0, perUserCapUSD: CAP,
    });
    approx(snap.potSpent, 0, 1e-9, "T6: pot fully released on settle(0)");
    approx(snap.userSpent, 0, 1e-9, "T6: user not charged on settle(0)");
  }

  // ── Test 7: stale reservations are swept + refunded after the TTL ──────────
  {
    const ctx = makeCtx({ POT_TOTAL_USD: 100 });
    const led = new Ledger(ctx, { POT_TOTAL_USD: 100 });
    // Simulate a leaked hold: a reservation row older than 10min + its pot debit.
    const old = Date.now() - 11 * 60 * 1000;
    ctx._db.prepare(
      "INSERT INTO reservations (id, user_id, month, amount, created_at) VALUES (?, ?, ?, ?, ?)"
    ).run("leaked", "u1", UTC_MONTH, 0.40, old);
    ctx._db.prepare("UPDATE meta SET value = value + 0.40 WHERE key = 'pot_spent'").run();
    const status = await led.status(); // status() sweeps first
    approx(status.potSpent, 0, 1e-9, "T7: stale hold refunded to the pot");
    ok(status.activeReservations === 0, "T7: stale reservation removed");
  }

  // ── Test 8: distinct-user counts (all-time vs this month) ──────────────────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    await led.settle({ userId: "uA", month: UTC_MONTH, actualCostUSD: 0.10, perUserCapUSD: CAP });
    await led.settle({ userId: "uB", month: UTC_MONTH, actualCostUSD: 0.10, perUserCapUSD: CAP });
    await led.settle({ userId: "uC", month: "2025-01", actualCostUSD: 0.10, perUserCapUSD: CAP });
    const status = await led.status();
    ok(status.usersAllTime === 3, `T8: usersAllTime == 3 (got ${status.usersAllTime})`);
    ok(status.usersThisMonth === 2, `T8: usersThisMonth == 2 (got ${status.usersThisMonth})`);
    ok(status.month === UTC_MONTH, `T8: status month is current UTC month (got ${status.month})`);
  }

  // ── Test 9: topup raises the pot total ─────────────────────────────────────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 10 }), { POT_TOTAL_USD: 10 });
    const status = await led.topup({ amountUSD: 5 });
    approx(status.potTotal, 15, 1e-9, "T9: topup adds to pot_total (10 + 5)");
    approx(status.potRemaining, 15, 1e-9, "T9: potRemaining reflects topup");
  }

  // ── Test 10: usage() exposes userAvailableNow under pacing ─────────────────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    const accrued = CAP * (5 / 30); // ≈ 0.4583
    await led.settle({ userId: "u1", month: UTC_MONTH, actualCostUSD: 0.20, perUserCapUSD: CAP });
    const snap = await led.usage({ userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP, accruedCapUSD: accrued });
    approx(snap.userSpent, 0.20, 1e-9, "T10: usage reports userSpent");
    approx(snap.userAvailableNow, accrued - 0.20, 1e-6, "T10: userAvailableNow == accrued − spent");
    approx(snap.userRemaining, CAP - 0.20, 1e-9, "T10: userRemaining == cap − spent");
  }

  // ── Test 11: per-user sliding-window rate limit ───────────────────────────
  // A virtual clock (nowMs) lets us prove the window deterministically. With a
  // limit of 3/min: 3 admitted, the 4th blocked, a different user unaffected,
  // and u1 admitted again once the window rolls forward.
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 1000 }), { POT_TOTAL_USD: 1000 });
    const base = 1_000_000;
    const call = (uid, t) => led.preflight({
      userId: uid, month: UTC_MONTH, perUserCapUSD: CAP,
      accruedCapUSD: CAP, estMaxCostUSD: 0.001, rateLimitPerMin: 3, nowMs: t,
    });
    const r1 = await call("u1", base + 0);
    const r2 = await call("u1", base + 1000);
    const r3 = await call("u1", base + 2000);
    ok(r1.allowed && r2.allowed && r3.allowed, "T11: first 3 requests within the window allowed");
    const r4 = await call("u1", base + 3000);
    ok(r4.allowed === false, "T11: 4th request within the window blocked");
    ok(r4.reason === "rate_limited", `T11: reason is rate_limited (got ${r4.reason})`);
    ok((r4.retryAfterMs || 0) > 0, "T11: blocked response carries retryAfterMs");
    const rB = await call("u2", base + 3000);
    ok(rB.allowed === true, "T11: per-user isolation — u2 not limited by u1's burst");
    const r5 = await call("u1", base + 61_000);
    ok(r5.allowed === true, "T11: window rolls forward — u1 admitted again after 60s");
  }

  // ── Test 12: rate limit disabled (limit 0) never blocks on volume ──────────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 1000 }), { POT_TOTAL_USD: 1000 });
    let everRateLimited = false;
    for (let i = 0; i < 50; i++) {
      const r = await led.preflight({
        userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP,
        accruedCapUSD: CAP, estMaxCostUSD: 0.001, rateLimitPerMin: 0, nowMs: 2_000_000 + i,
      });
      if (r.reason === "rate_limited") everRateLimited = true;
    }
    ok(everRateLimited === false, "T12: rateLimitPerMin=0 disables the volume guard");
  }

  // ── Test 13: proxy hardening guards present in index.js / jwt.js ───────────
  // The harness can't drive the full Worker request path, so these assert the
  // shipped source still carries the input bounds, rate wiring, no-leak, and
  // alg-pinning hardening (a regression trip-wire if someone reverts them).
  {
    const indexSrc = readFileSync(INDEX_SRC, "utf8");
    ok(/rateLimitPerMin\s*:/.test(indexSrc), "T13: handleChat passes rateLimitPerMin into preflight");
    ok(/MAX_PROMPT_BYTES/.test(indexSrc), "T13: handleChat bounds prompt byte size");
    ok(/payload_too_large/.test(indexSrc), "T13: oversized/over-count payloads rejected");
    ok(/code:\s*"rate_limited"/.test(indexSrc), "T13: rate_limited surfaced to the app (429)");
    ok(!/detail:\s*String\(/.test(indexSrc), "T13: no internal error 'detail' leaked to clients");
    ok(/isPricedModel\(/.test(indexSrc), "T13: handleChat fails CLOSED on a PRICING miss (isPricedModel guard)");
    ok(/model_misconfigured/.test(indexSrc), "T13: PRICING-miss surfaced as model_misconfigured (not billed at a guess)");
    const jwtSrc = readFileSync(JWT_SRC, "utf8");
    ok(/header\.alg\s*!==\s*"HS256"/.test(jwtSrc), "T13: verifySession pins the JWT alg to HS256");
  }

  // ── Test 14: pot stays a HARD ceiling when actual cost > reserved est ──────
  // Ledger-audit regression. settle(actual-est) must never push pot_spent above
  // pot_total even if a reservation under-estimated the real cost.
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 0.20 }), { POT_TOTAL_USD: 0.20 });
    const pre = await led.preflight({
      userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP, accruedCapUSD: CAP,
      estMaxCostUSD: 0.20, rateLimitPerMin: 0, nowMs: 3_000_000,
    });
    ok(pre.allowed, "T14: admitted at full-pot reservation");
    approx(pre.potSpent, 0.20, 1e-9, "T14: pot reserved to total (0.20)");
    const snap = await led.settle({
      reservationId: pre.reservationId, userId: "u1", month: UTC_MONTH,
      actualCostUSD: 0.30, perUserCapUSD: CAP, // real cost EXCEEDS the reservation
    });
    approx(snap.potSpent, 0.20, 1e-9, "T14: pot_spent CLAMPED to pot_total (never exceeds 0.20)");
    ok(snap.potRemaining >= 0, "T14: potRemaining never negative");
  }

  // ── Test 15: a rate slot is consumed ONLY on an admitted call ──────────────
  // Regression: a request rejected for user_cap must NOT burn a rate slot.
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    await led.settle({ userId: "u1", month: UTC_MONTH, actualCostUSD: CAP, perUserCapUSD: CAP }); // exhaust cap
    const now = 4_000_000;
    for (let i = 0; i < 5; i++) {
      const r = await led.preflight({
        userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP, accruedCapUSD: CAP,
        estMaxCostUSD: 0.01, rateLimitPerMin: 3, nowMs: now + i,
      });
      ok(r.reason === "user_cap", `T15: capped request ${i} rejected for user_cap (not rate_limited)`);
    }
    // Prove no rate slots were burned: u1 (now under cap via a fresh month) gets
    // 3 admits, not 0. Use a different month so the cap no longer blocks.
    const m2 = "2099-12";
    let admits = 0;
    for (let i = 0; i < 4; i++) {
      const r = await led.preflight({
        userId: "u1", month: m2, perUserCapUSD: CAP, accruedCapUSD: CAP,
        estMaxCostUSD: 0.01, rateLimitPerMin: 3, nowMs: now + 100 + i,
      });
      if (r.allowed) admits++;
    }
    ok(admits === 3, `T15: exactly 3 admitted in-window (cap-rejects burned 0 slots); got ${admits}`);
  }

  // ── Test 16: fallback settle never double-books (bookIfMissing:false) ──────
  // Regression: handleChat's finally-fallback re-settles; if the primary settle
  // already applied (reservation row gone), the fallback must be a no-op.
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    const pre = await led.preflight({
      userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP, accruedCapUSD: CAP,
      estMaxCostUSD: 0.50, rateLimitPerMin: 0, nowMs: 5_000_000,
    });
    await led.settle({ // primary settle: books real cost, deletes reservation
      reservationId: pre.reservationId, userId: "u1", month: UTC_MONTH,
      actualCostUSD: 0.05, perUserCapUSD: CAP,
    });
    const snap = await led.settle({ // fallback retry on the SAME id
      reservationId: pre.reservationId, userId: "u1", month: UTC_MONTH,
      actualCostUSD: 0.05, perUserCapUSD: CAP, bookIfMissing: false,
    });
    approx(snap.potSpent, 0.05, 1e-9, "T16: fallback no-op — pot still 0.05 (no double-book)");
    approx(snap.userSpent, 0.05, 1e-9, "T16: fallback no-op — user charged 0.05 once");
  }

  // ── Test 17: costUSD bills a real rate for an allowed-but-unpriced model ────
  // Regression: a PRICING miss must not return $0 (that would book spend as free).
  {
    const { costUSD } = await import(
      pathToFileURL(join(__dirname, "..", "src", "pricing.js")).href
    );
    const c = costUSD({ prompt_tokens: 1_000_000, completion_tokens: 0 }, "some-future-model");
    ok(c > 0, `T17: unpriced model billed at a real (non-zero) rate; got ${c}`);
  }

  // ── Test 18: daily_cap & pot_exhausted rejections burn ZERO rate slots ─────
  // Companion to T15 (which proves it for user_cap). The user named these two
  // reasons specifically: a request rejected for daily pacing OR an exhausted
  // pot never reached DeepSeek, so it must not consume a sliding-window rate
  // slot — else a paced-out or pot-starved user is ALSO wrongly throttled. All
  // three rejection reasons return before #recordRequest, so prove both here.
  {
    // (a) daily_cap: accrued allowance is 0 (monthly cap NOT exhausted).
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    const now = 6_000_000;
    for (let i = 0; i < 5; i++) {
      const r = await led.preflight({
        userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP, accruedCapUSD: 0,
        estMaxCostUSD: 0.01, rateLimitPerMin: 3, nowMs: now + i,
      });
      ok(r.reason === "daily_cap", `T18a: paced-out request ${i} rejected for daily_cap (got ${r.reason})`);
    }
    let admits = 0;
    for (let i = 0; i < 4; i++) {
      const r = await led.preflight({ // unlock the daily allowance, SAME window
        userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP, accruedCapUSD: CAP,
        estMaxCostUSD: 0.01, rateLimitPerMin: 3, nowMs: now + 100 + i,
      });
      if (r.allowed) admits++;
    }
    ok(admits === 3, `T18a: daily_cap rejects burned 0 rate slots (3 admits in-window); got ${admits}`);
  }
  {
    // (b) pot_exhausted: pot can't cover the reservation (user cap is fine).
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 0.001 }), { POT_TOTAL_USD: 0.001 });
    const now = 7_000_000;
    for (let i = 0; i < 5; i++) {
      const r = await led.preflight({
        userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP, accruedCapUSD: CAP,
        estMaxCostUSD: 0.50, rateLimitPerMin: 3, nowMs: now + i,
      });
      ok(r.reason === "pot_exhausted", `T18b: pot-starved request ${i} rejected for pot_exhausted (got ${r.reason})`);
    }
    await led.topup({ amountUSD: 100 }); // refill so calls can now be admitted
    let admits = 0;
    for (let i = 0; i < 4; i++) {
      const r = await led.preflight({
        userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP, accruedCapUSD: CAP,
        estMaxCostUSD: 0.01, rateLimitPerMin: 3, nowMs: now + 100 + i,
      });
      if (r.allowed) admits++;
    }
    ok(admits === 3, `T18b: pot_exhausted rejects burned 0 rate slots (3 admits in-window); got ${admits}`);
  }

  // ── Test 19: isPricedModel — the loud guard that fails index.js closed ─────
  // A PRICING miss must be detectable so handleChat can refuse (503) instead of
  // billing real spend at the pro fallback rate nobody chose.
  {
    const { isPricedModel } = await import(
      pathToFileURL(join(__dirname, "..", "src", "pricing.js")).href
    );
    ok(isPricedModel("deepseek-v4-pro") === true, "T19: explicitly-priced model recognized");
    ok(isPricedModel("some-future-model") === false, "T19: unpriced model flagged (drives 503 model_misconfigured)");
  }

  // ── Accrual-formula sanity (mirrors index.js utcMonthFractionElapsed) ──────
  // Proves day 1 → 1/daysInMonth and the last day → exactly 1.0 for varied
  // month lengths. Also assert the shipped helper exists in index.js.
  {
    const indexSrc = readFileSync(INDEX_SRC, "utf8");
    ok(/function\s+utcMonthFractionElapsed\s*\(/.test(indexSrc),
       "ACCRUAL: index.js still defines utcMonthFractionElapsed()");
    ok(/accruedCapUSD\s*:\s*accruedCap/.test(indexSrc),
       "ACCRUAL: handleChat passes accruedCapUSD into preflight");
    const frac = (y, m /*1-based*/, day) => {
      const daysInMonth = new Date(Date.UTC(y, m, 0)).getUTCDate();
      return Math.min(1, Math.max(0, day / daysInMonth));
    };
    approx(frac(2026, 1, 1), 1 / 31, 1e-9, "ACCRUAL: Jan day 1 == 1/31");
    approx(frac(2026, 1, 31), 1, 1e-9, "ACCRUAL: Jan day 31 == 1.0");
    approx(frac(2026, 2, 28), 1, 1e-9, "ACCRUAL: Feb(28) last day == 1.0");
    approx(frac(2024, 2, 29), 1, 1e-9, "ACCRUAL: Feb(29) leap last day == 1.0");
    approx(frac(2026, 4, 15), 15 / 30, 1e-9, "ACCRUAL: Apr day 15 == 0.5");
  }

  // ── Firewall: kill switch (admin pause / resume) ───────────────────────────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    await led.setEnabled({ enabled: false });
    const blocked = await led.preflight({
      userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP, accruedCapUSD: CAP, estMaxCostUSD: 0.05,
    });
    ok(blocked.allowed === false && blocked.reason === "disabled", "FW: kill switch blocks (reason disabled)");
    ok((await led.status()).enabled === false, "FW: status shows enabled=false when paused");
    await led.setEnabled({ enabled: true });
    const allowed = await led.preflight({
      userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP, accruedCapUSD: CAP, estMaxCostUSD: 0.05,
    });
    ok(allowed.allowed === true, "FW: resume re-allows calls");
    ok((await led.status()).enabled === true, "FW: status shows enabled=true after resume");
  }

  // ── Firewall: settable pot ceiling (admin setcap lowers max spend) ─────────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    approx((await led.setCap({ totalUSD: 5 })).potTotal, 5, 1e-9, "FW: setcap lowers pot ceiling to 5");
    const pre = await led.preflight({
      userId: "u1", month: UTC_MONTH, perUserCapUSD: CAP, accruedCapUSD: CAP, estMaxCostUSD: 6,
    });
    ok(pre.allowed === false && pre.reason === "pot_exhausted", "FW: est above lowered ceiling → pot_exhausted");
  }

  // ── Firewall: hard daily GLOBAL cap (reason daily_pot_cap) ─────────────────
  {
    const led = new Ledger(makeCtx({ POT_TOTAL_USD: 100 }), { POT_TOTAL_USD: 100 });
    const args = (est, userId = "u1") => ({
      userId, month: UTC_MONTH, perUserCapUSD: CAP, accruedCapUSD: CAP, estMaxCostUSD: est, dailyCapUSD: 1.0,
    });
    const a = await led.preflight(args(0.6));
    ok(a.allowed === true, "FW: first call under daily cap allowed");
    const b = await led.preflight(args(0.6));
    ok(b.allowed === false && b.reason === "daily_pot_cap", "FW: exceeding daily cap → daily_pot_cap");
    const c = await led.preflight(args(0.6, "u2"));
    ok(c.allowed === false && c.reason === "daily_pot_cap", "FW: daily cap is GLOBAL (blocks other users too)");
    await led.settle({ reservationId: a.reservationId, userId: "u1", month: UTC_MONTH, actualCostUSD: 0, perUserCapUSD: CAP });
    const d = await led.preflight(args(0.6));
    ok(d.allowed === true, "FW: releasing a hold refunds the daily bucket");
  }

  // ── Report ─────────────────────────────────────────────────────────────────
  console.log(`\n${failures.length === 0 ? "PASS" : "FAIL"} — ${passed} assertions passed, ${failures.length} failed`);
  if (failures.length) {
    for (const f of failures) console.error("   - " + f);
    process.exit(1);
  }
}

main().catch((e) => { console.error("HARNESS ERROR:", e); process.exit(1); });
