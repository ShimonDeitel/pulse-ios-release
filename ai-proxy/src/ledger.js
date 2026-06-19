import { DurableObject } from "cloudflare:workers";

// ─────────────────────────────────────────────────────────────────────────────
// Ledger: the single source of truth for money. One global instance (named
// "global") holds:
//   • the pot   — your lump-sum deposit; pot_spent can never exceed pot_total
//   • per-user monthly spend — enforces the $2.75/user/month cap
//   • reservations — in-flight holds so concurrent calls can't overshoot the pot
//
// A Durable Object runs single-threaded per instance, so every method below is
// effectively atomic: no locks, no races. That serialization is exactly why the
// pot is a HARD ceiling and not a best-effort estimate.
//
// reserve→settle: before calling DeepSeek we reserve a conservative MAX cost
// against the pot. After the call we settle to the ACTUAL cost (refunding the
// difference). If the call dies, the worker settles with cost 0 to release the
// hold; any reservation that still leaks is swept after 10 minutes.
// ─────────────────────────────────────────────────────────────────────────────

const RESERVATION_TTL_MS = 10 * 60 * 1000;
const RATE_WINDOW_MS = 60 * 1000; // sliding window for per-user request rate limiting

export class Ledger extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    ctx.blockConcurrencyWhile(async () => this.#init());
  }

  #init() {
    this.sql.exec(
      `CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value REAL NOT NULL);`
    );
    this.sql.exec(
      `CREATE TABLE IF NOT EXISTS user_spend (
         user_id TEXT NOT NULL, month TEXT NOT NULL, spent REAL NOT NULL DEFAULT 0,
         PRIMARY KEY (user_id, month));`
    );
    this.sql.exec(
      `CREATE TABLE IF NOT EXISTS reservations (
         id TEXT PRIMARY KEY, user_id TEXT NOT NULL, month TEXT NOT NULL,
         amount REAL NOT NULL, created_at INTEGER NOT NULL);`
    );
    // Sliding-window request log for per-user rate limiting. One row per admitted
    // request; rows older than the window are pruned on every preflight, so the
    // table stays tiny. This caps request VOLUME (abuse / cost-amplification via
    // many calls) independently of the dollar cap.
    this.sql.exec(
      `CREATE TABLE IF NOT EXISTS rate_events (
         user_id TEXT NOT NULL, ts INTEGER NOT NULL);`
    );
    this.sql.exec(
      `CREATE INDEX IF NOT EXISTS idx_rate_user_ts ON rate_events (user_id, ts);`
    );
    // Seed pot_total once, from the configured deposit. Never reseeds on restart.
    const seed = Number(this.env.POT_TOTAL_USD) || 0;
    if (this.#getMeta("pot_total") === null) this.#setMeta("pot_total", seed);
    if (this.#getMeta("pot_spent") === null) this.#setMeta("pot_spent", 0);
  }

  #getMeta(key) {
    const rows = this.sql.exec("SELECT value FROM meta WHERE key = ?", key).toArray();
    return rows.length ? Number(rows[0].value) : null;
  }
  #setMeta(key, value) {
    this.sql.exec(
      "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
      key,
      value
    );
  }
  #addPotSpent(delta) {
    // Floor at 0 (refunds can't drive it negative) AND cap at pot_total, so a
    // settle whose actual cost exceeds the reserved est can never push pot_spent
    // above the deposit — the pot stays a HARD ceiling even if a reservation
    // under-estimated. Without the MIN, (actual - est) > 0 would breach it.
    this.sql.exec(
      `UPDATE meta SET value = MIN(
         (SELECT value FROM meta WHERE key = 'pot_total'),
         MAX(0, value + ?)
       ) WHERE key = 'pot_spent'`,
      delta
    );
  }

  // ── Daily GLOBAL cap — a conservative safety ceiling on TOP of the lifetime
  //    pot. Tracks dollars reserved/settled in the current UTC day and resets
  //    lazily when the day rolls. Keyed as an integer YYYYMMDD so it lives in the
  //    REAL-valued `meta` table alongside everything else.
  #todayNum() {
    const d = new Date();
    return d.getUTCFullYear() * 10000 + (d.getUTCMonth() + 1) * 100 + d.getUTCDate();
  }
  #daySpent() {
    const today = this.#todayNum();
    if (this.#getMeta("day_key") !== today) {
      this.#setMeta("day_key", today);
      this.#setMeta("day_spent", 0);
      return 0;
    }
    return this.#getMeta("day_spent") ?? 0;
  }
  #addDaySpent(delta) {
    const cur = this.#daySpent(); // resets the bucket first if the day rolled
    this.#setMeta("day_spent", Math.max(0, cur + delta));
  }

  // ── Master kill switch. Defaults ON when unset; admin can pause/resume live.
  #aiEnabled() {
    const v = this.#getMeta("ai_enabled");
    return v === null ? true : v !== 0;
  }

  #userSpent(userId, month) {
    const rows = this.sql
      .exec("SELECT spent FROM user_spend WHERE user_id = ? AND month = ?", userId, month)
      .toArray();
    return rows.length ? Number(rows[0].spent) : 0;
  }
  #addUserSpent(userId, month, delta) {
    this.sql.exec(
      `INSERT INTO user_spend (user_id, month, spent) VALUES (?, ?, ?)
       ON CONFLICT(user_id, month) DO UPDATE SET spent = spent + excluded.spent`,
      userId,
      month,
      delta
    );
  }
  #sweepStaleReservations(now = Date.now()) {
    const cutoff = now - RESERVATION_TTL_MS;
    const stale = this.sql
      .exec("SELECT amount FROM reservations WHERE created_at < ?", cutoff)
      .toArray();
    let refunded = 0;
    for (const r of stale) refunded += Number(r.amount) || 0;
    if (refunded > 0) this.#addPotSpent(-refunded);
    this.sql.exec("DELETE FROM reservations WHERE created_at < ?", cutoff);
  }

  // ── Per-user sliding-window rate limiting ──────────────────────────────────
  // Counts a user's admitted requests in the last RATE_WINDOW_MS. Old rows are
  // pruned globally each call so the table can't grow unbounded. Single-threaded
  // DO ⇒ this count-then-insert is atomic, so the limit can't be raced past.
  #countRecentRequests(userId, windowStart) {
    const rows = this.sql
      .exec("SELECT COUNT(*) AS c FROM rate_events WHERE user_id = ? AND ts >= ?", userId, windowStart)
      .toArray();
    return rows.length ? Number(rows[0].c) : 0;
  }
  #recordRequest(userId, now) {
    this.sql.exec("INSERT INTO rate_events (user_id, ts) VALUES (?, ?)", userId, now);
  }
  #pruneRateEvents(windowStart) {
    // Exclude anon-issuance rows: they live on a longer (1-hour) window managed
    // by anonIssueAllowed(); the short per-user window must not evict them early.
    this.sql.exec("DELETE FROM rate_events WHERE ts < ? AND user_id NOT LIKE 'anon-issue:%'", windowStart);
  }

  // ── Anonymous-session ISSUANCE rate limit (per client IP, 1-hour window) ─────
  // Distinct from the per-user request rate limit, but reuses the rate_events
  // table by storing the IP key in user_id with an "anon-issue:" prefix. Stops a
  // bot from minting unlimited anonymous free sessions and draining the shared
  // free-provider keys. Single-threaded DO ⇒ count-then-insert is atomic.
  async anonIssueAllowed({ key, perHour, nowMs }) {
    const now = Number.isFinite(nowMs) ? nowMs : Date.now();
    const windowStart = now - 60 * 60 * 1000;
    this.sql.exec("DELETE FROM rate_events WHERE ts < ? AND user_id LIKE 'anon-issue:%'", windowStart);
    const limit = Math.max(0, Math.floor(Number(perHour) || 0));
    const count = this.#countRecentRequests(key, windowStart);
    if (limit > 0 && count >= limit) {
      return { allowed: false, retryAfterSeconds: 3600 };
    }
    this.#recordRequest(key, now);
    return { allowed: true };
  }

  // `monthlyCap` is the hard total for the month ($2.75). `accruedCap` is how much
  // of that has "unlocked" so far this month under daily pacing — it accrues ~1/30
  // per day and carries forward (see index.js: cap × dayOfMonth/daysInMonth). When
  // omitted it defaults to the full monthly cap (no pacing).
  #snapshot(userId, month, monthlyCap, accruedCap) {
    const potTotal = this.#getMeta("pot_total") ?? 0;
    const potSpent = this.#getMeta("pot_spent") ?? 0;
    const userSpent = this.#userSpent(userId, month);
    const accrued = accruedCap == null ? monthlyCap : Math.max(0, accruedCap);
    return {
      potTotal,
      potSpent,
      potRemaining: Math.max(0, potTotal - potSpent),
      userSpent,
      // Remaining against the whole month (drives the "monthly limit" wall).
      userRemaining: Math.max(0, monthlyCap - userSpent),
      // Spendable right now under daily pacing (drives the "daily limit" note).
      userAvailableNow: Math.max(0, Math.min(monthlyCap, accrued) - userSpent),
    };
  }

  /**
   * Decide whether a call may proceed, and if so HOLD its max cost against the
   * pot. Returns { allowed, reason?, reservationId?, ...snapshot }.
   */
  async preflight({ userId, month, perUserCapUSD, accruedCapUSD, estMaxCostUSD, rateLimitPerMin, dailyCapUSD, nowMs }) {
    const now = Number.isFinite(nowMs) ? nowMs : Date.now();
    this.#sweepStaleReservations(now);
    const monthlyCap = Number(perUserCapUSD) || 0;
    const accruedCap = accruedCapUSD == null ? monthlyCap : Math.max(0, Number(accruedCapUSD) || 0);
    const est = Math.max(0, Number(estMaxCostUSD) || 0);
    const snap = this.#snapshot(userId, month, monthlyCap, accruedCap);

    // Master kill switch — refuse everything when AI is paused (admin-toggled,
    // takes effect instantly, no redeploy).
    if (!this.#aiEnabled()) {
      return { allowed: false, reason: "disabled", ...snap };
    }

    // Rate limit FIRST — cheapest, abuse-resistant gate. Caps request volume per
    // user regardless of budget so a stolen/forged session can't hammer the proxy
    // (or amplify cost with a burst of calls). Counting admitted requests in a
    // sliding window means it self-heals as the window rolls forward.
    const limit = Math.floor(Number(rateLimitPerMin) || 0);
    const windowStart = now - RATE_WINDOW_MS;
    if (limit > 0) {
      this.#pruneRateEvents(windowStart);
      if (this.#countRecentRequests(userId, windowStart) >= limit) {
        return { allowed: false, reason: "rate_limited", retryAfterMs: RATE_WINDOW_MS, ...snap };
      }
      // NOTE: do NOT record the request here. A request that passes the rate gate
      // but is then rejected for cap/pot below never reached DeepSeek, so it must
      // not burn a rate slot — otherwise a capped-out user is also wrongly
      // throttled. The slot is recorded only on the admitted path (below).
    }

    // Per-user monthly cap (soft: committed-spend based, lets users use it all month).
    if (snap.userRemaining <= 0) {
      return { allowed: false, reason: "user_cap", ...snap };
    }
    // Daily pacing: the month's allowance unlocks ~1/30 per day (carry-forward).
    // Hitting this is a soft "come back tomorrow" — the wall lifts as days pass.
    if (snap.userAvailableNow <= 0) {
      return { allowed: false, reason: "daily_cap", ...snap };
    }
    // Global pot (hard: must cover the reserved max, so it cannot be overshot).
    if (snap.potRemaining < est) {
      return { allowed: false, reason: "pot_exhausted", ...snap };
    }
    // Hard daily GLOBAL cap (safety net on top of the lifetime pot): no more than
    // dailyCap dollars may be reserved across ALL users in one UTC day, so a bad
    // day (abuse, runaway loop) can bleed at most that much before it self-heals
    // at midnight. "0" disables it.
    const dailyCap = Math.max(0, Number(dailyCapUSD) || 0);
    if (dailyCap > 0 && this.#daySpent() + est > dailyCap) {
      return { allowed: false, reason: "daily_pot_cap", daySpent: this.#daySpent(), dailyCap, ...snap };
    }

    // Admitted: record the rate slot now (count-then-insert is atomic on the
    // single-threaded DO, so the limit still can't be raced past).
    if (limit > 0) this.#recordRequest(userId, now);

    const reservationId = crypto.randomUUID();
    this.sql.exec(
      "INSERT INTO reservations (id, user_id, month, amount, created_at) VALUES (?, ?, ?, ?, ?)",
      reservationId,
      userId,
      month,
      est,
      now
    );
    this.#addPotSpent(est);
    this.#addDaySpent(est); // mirror the hold into today's safety bucket
    return {
      allowed: true,
      reservationId,
      ...this.#snapshot(userId, month, monthlyCap, accruedCap),
    };
  }

  /**
   * Reconcile a reservation to the real cost. Pass actualCostUSD: 0 to release a
   * hold (e.g. the DeepSeek call failed). Idempotent-ish: a missing reservation
   * (already swept) just books the actual cost.
   */
  // `bookIfMissing` controls the no-hold-found case:
  //   • true  (default): book the actual cost directly — used for the normal
  //     path and the sweep-then-settle race, so the pot still reflects real spend.
  //   • false: no-op — used by handleChat's FALLBACK settle (when the primary
  //     settle threw after a billed 2xx call). If the reservation row is already
  //     gone, the primary settle DID apply, so re-booking here would double-charge.
  async settle({ reservationId, userId, month, actualCostUSD, perUserCapUSD, bookIfMissing = true }) {
    const cap = Number(perUserCapUSD) || 0;
    const actual = Math.max(0, Number(actualCostUSD) || 0);

    const held = reservationId
      ? this.sql.exec("SELECT amount FROM reservations WHERE id = ?", reservationId).toArray()
      : [];
    if (held.length) {
      const est = Number(held[0].amount) || 0;
      this.#addPotSpent(actual - est); // refund the unused part of the hold
      this.#addDaySpent(actual - est); // ...and the same against today's bucket
      this.sql.exec("DELETE FROM reservations WHERE id = ?", reservationId);
    } else if (bookIfMissing) {
      // No hold found — book the actual cost directly so the pot still reflects it.
      this.#addPotSpent(actual);
      this.#addDaySpent(actual);
    } else {
      // Fallback retry and the hold is already gone → the primary settle applied.
      // Do nothing: re-booking would double-charge the pot and the user.
      return this.#snapshot(userId, month, cap);
    }
    if (actual > 0) this.#addUserSpent(userId, month, actual);
    return this.#snapshot(userId, month, cap);
  }

  /** Read-only usage for a user (powers the app's budget meter). */
  async usage({ userId, month, perUserCapUSD, accruedCapUSD }) {
    this.#sweepStaleReservations();
    const monthlyCap = Number(perUserCapUSD) || 0;
    const accruedCap = accruedCapUSD == null ? monthlyCap : Math.max(0, Number(accruedCapUSD) || 0);
    return this.#snapshot(userId || "", month || "", monthlyCap, accruedCap);
  }

  /** Admin: add to the pot total (top up the deposit) without a redeploy. */
  async topup({ amountUSD }) {
    const add = Number(amountUSD) || 0;
    const total = (this.#getMeta("pot_total") ?? 0) + add;
    this.#setMeta("pot_total", total);
    return this.#status();
  }

  /** Admin: SET the pot ceiling directly (raise OR lower) without a redeploy.
   *  This is how you tighten the absolute max spend to e.g. $5 live. */
  async setCap({ totalUSD }) {
    this.#setMeta("pot_total", Math.max(0, Number(totalUSD) || 0));
    return this.#status();
  }

  /** Admin: instant kill switch — pause/resume ALL AI with no redeploy. */
  async setEnabled({ enabled }) {
    this.#setMeta("ai_enabled", enabled ? 1 : 0);
    return this.#status();
  }

  /** Admin: overall pot state + how many distinct users are using AI. */
  async status() {
    this.#sweepStaleReservations();
    return this.#status();
  }
  #utcMonth() {
    const d = new Date();
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
  }
  #status() {
    const potTotal = this.#getMeta("pot_total") ?? 0;
    const potSpent = this.#getMeta("pot_spent") ?? 0;
    const active = this.sql.exec("SELECT COUNT(*) AS c FROM reservations").toArray();
    // Distinct users who have ever spent (all-time) and this calendar month.
    // This is your real-time "who's actually using AI" count — the private
    // CloudKit data is invisible to you, so the proxy is the only place to see it.
    const month = this.#utcMonth();
    const usersAll = this.sql.exec("SELECT COUNT(DISTINCT user_id) AS c FROM user_spend").toArray();
    const usersMonth = this.sql
      .exec("SELECT COUNT(DISTINCT user_id) AS c FROM user_spend WHERE month = ?", month)
      .toArray();
    return {
      potTotal,
      potSpent,
      potRemaining: Math.max(0, potTotal - potSpent),
      enabled: this.#aiEnabled(),
      daySpent: this.#daySpent(),
      activeReservations: active.length ? Number(active[0].c) : 0,
      usersAllTime: usersAll.length ? Number(usersAll[0].c) : 0,
      usersThisMonth: usersMonth.length ? Number(usersMonth[0].c) : 0,
      month,
    };
  }
}
