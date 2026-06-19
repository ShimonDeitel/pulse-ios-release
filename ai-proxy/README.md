# pulse-ai-proxy

A Cloudflare Worker that sits between the Pulse iOS app and DeepSeek so that:

1. **The shared DeepSeek key lives only on the server.** The app never ships it, so it can't be extracted from the bundle.
2. **Every paying user is metered to a monthly cap** (`PER_USER_CAP_USD`, currently **$2.75**).
3. **A global pot is a hard ceiling.** The proxy refuses to spend past `POT_TOTAL_USD` no matter how many users hit it — so a runaway month can't drain your DeepSeek balance. You decide exactly how much you're willing to lose.

> **You fund DeepSeek and the pot. The proxy never spends money you didn't deposit.** Nothing here charges a card or moves money on its own — `POT_TOTAL_USD` is just a number that says "stop here."

---

## How it works

```
iOS app                         pulse-ai-proxy (Worker)                DeepSeek
  │  Sign in with Apple              │                                    │
  │  POST /v1/session  ───────────►  │  verify Apple identity token       │
  │    { identityToken }             │  (RS256, against Apple JWKS)        │
  │  ◄───────── { sessionToken } ──  │  mint 60-day HS256 session JWT      │
  │                                  │                                    │
  │  POST /v1/chat  ──────────────►  │  verify session JWT                │
  │   Authorization: Bearer <jwt>    │  Ledger.preflight (reserve max $)  │
  │   { model, messages, ... }       │  ───────────────────────────────► │
  │                                  │  ◄──────── usage + completion ──── │
  │  ◄──── DeepSeek JSON + headers ─ │  Ledger.settle (book actual $)     │
```

**The Ledger** is a single SQLite-backed Durable Object named `"global"`. Durable
Objects run single-threaded per instance, so every ledger method is effectively
atomic — no locks, no races. That serialization is exactly what makes the pot a
real ceiling instead of a best-effort estimate.

**reserve → settle:** before each call the proxy *reserves* a conservative maximum
cost against the pot; after the call it *settles* to the actual cost and refunds
the difference. If a call dies mid-flight, the hold is released (and any leaked
hold is swept after 10 minutes). Concurrent calls therefore can't overshoot the
pot even in the worst case.

- **Per-user cap is "soft":** based on committed spend, so a user can use their
  full monthly allowance and the last call isn't blocked early.
- **Global pot is "hard":** based on reserved max, so it can never be exceeded.

---

## Prerequisites (things only you can do)

1. **A Cloudflare account.** Sign up at <https://dash.cloudflare.com/sign-up>.
2. **The Workers Paid plan ($5/month).** SQLite-backed Durable Objects are not
   available on the free Workers plan. This is a real, honest cost of running the
   proxy. (If you ever want to avoid it, the ledger would need to move to a
   different store — but then you lose the per-instance atomicity that makes the
   pot bulletproof. The DO is the right tool.)
3. **A funded DeepSeek account + API key.** This is the only place real AI money
   is spent. The proxy will never let total spend exceed your pot, but DeepSeek
   itself must have a balance for calls to succeed.

> I can't (and won't) create your Cloudflare account, enter payment details, or
> fund DeepSeek for you. Those steps are yours.

---

## One-time setup

From this `ai-proxy/` directory:

```bash
# 1. Install the dev toolchain (wrangler only — there are no runtime deps).
npm install

# 2. Log in to Cloudflare (opens a browser; you authorize it).
npx wrangler login

# 3. Set the three secrets. Each prompts for the value (never stored in git).
npx wrangler secret put DEEPSEEK_API_KEY        # your funded DeepSeek key
npx wrangler secret put SESSION_SIGNING_SECRET  # see below to generate
npx wrangler secret put ADMIN_SECRET            # protects /admin/* — see below
```

Generate the two random secrets locally and paste them when prompted:

```bash
openssl rand -base64 48    # use the output for SESSION_SIGNING_SECRET
openssl rand -base64 48    # use a DIFFERENT output for ADMIN_SECRET
```

- `SESSION_SIGNING_SECRET` signs the app's session tokens. Keep it stable —
  rotating it invalidates every issued session (apps just re-exchange, no harm).
- `ADMIN_SECRET` is the bearer token for `/admin/status` and `/admin/topup`.
  Keep it private; anyone with it can read pot state and raise the ceiling.

### Configure the non-secret knobs

These live in [`wrangler.toml`](./wrangler.toml) under `[vars]`:

| Var | Default | Meaning |
|-----|---------|---------|
| `POT_TOTAL_USD` | `100` | Lump sum the proxy may spend, total, ever (until topped up). **This is your bankruptcy guard — set it to the most you're willing to spend.** |
| `PER_USER_CAP_USD` | `2.75` | Monthly AI ceiling per paying user. |
| `APPLE_BUNDLE_ID` | `com.shimon.pulse` | Must equal the app's bundle id; Apple tokens whose `aud` differs are rejected. |
| `MAX_OUTPUT_TOKENS` | `16384` | Server-side clamp on `max_tokens` to bound per-call cost. |
| `ALLOWED_MODELS` | `deepseek-v4-pro,deepseek-v4-flash` | Models a caller may request. |

> `POT_TOTAL_USD` only seeds the pot on the **very first** deploy. After that the
> stored value wins, so editing it here won't change a running pot — use
> `/admin/topup` instead (below). This is deliberate: a redeploy can't silently
> reset your spend tracking.

### Deploy

```bash
npm run deploy
```

Wrangler prints your Worker URL, e.g. `https://pulse-ai-proxy.<subdomain>.workers.dev`.
That URL is what the iOS app points at.

---

## Operating the pot

All `/admin` calls need the admin secret, either header form works:

```bash
BASE="https://pulse-ai-proxy.<subdomain>.workers.dev"
ADMIN="<your ADMIN_SECRET>"

# Check pot + spend + active reservations.
curl -s "$BASE/admin/status" -H "x-admin-secret: $ADMIN"

# Add $50 to the ceiling (no redeploy needed).
curl -s -X POST "$BASE/admin/topup" \
  -H "x-admin-secret: $ADMIN" \
  -H "content-type: application/json" \
  -d '{"amountUSD": 50}'
```

`/admin/status` returns:

```json
{ "potTotal": 100, "potSpent": 12.3, "potRemaining": 87.7, "activeReservations": 2 }
```

When `potRemaining` hits 0 the proxy returns `402 pot_exhausted` to every user
until you top up. That's the safety net doing its job — not an outage to panic over.

---

## Endpoints

| Method & path | Auth | Purpose |
|---------------|------|---------|
| `GET /health` | none | Liveness check. |
| `POST /v1/session` | Apple identity token in body | Exchange a fresh Sign-in-with-Apple token for a 60-day session JWT. |
| `POST /v1/chat` | `Authorization: Bearer <session JWT>` | Metered DeepSeek chat. Forces `stream:false` so usage can be metered; clamps `max_tokens`. |
| `GET /v1/budget` | `Authorization: Bearer <session JWT>` | The app's budget meter: user spent/remaining + pot remaining. |
| `GET /admin/status` | admin secret | Pot state. |
| `POST /admin/topup` | admin secret | Raise the pot ceiling. |

### Error contract (what the app keys off)

| Status | `code` | App behavior |
|--------|--------|--------------|
| `429` | `user_cap` | User used their monthly allowance → show the existing "limit reached" modal. |
| `402` | `pot_exhausted` | Pot empty → "AI temporarily unavailable" (operator must top up). |
| `401` | `unauthorized` | Missing/expired session → re-exchange via `/v1/session`. |
| upstream | (DeepSeek's own) | DeepSeek 402/429/5xx pass straight through with their status/body. |

On success, `/v1/chat` returns DeepSeek's JSON plus headers:
`x-pulse-cost-usd`, `x-pulse-user-remaining-usd`, `x-pulse-pot-remaining-usd`.

---

## Local development

```bash
cp .dev.vars.example .dev.vars   # then fill in real values; .dev.vars is gitignored
npm run dev                      # wrangler dev with a local DO + local vars
```

`npm run check` runs `node --check` on every source file (fast syntax gate). The
pricing math and JWT/ledger accounting were also validated with standalone Node
harnesses during development (pure logic, no Cloudflare runtime needed); the full
request path is exercised under `wrangler dev` / after deploy.

---

## Keeping pricing in lockstep

[`src/pricing.js`](./src/pricing.js) mirrors `DeepSeekModel` /
`DeepSeekUsage.costUSD(for:)` in the iOS app
(`pulse/Core/Networking/DeepSeekClient.swift`). **If you change a rate in one,
change it in the other**, or the app's advisory budget meter will drift from what
the proxy actually debits. The proxy's debit is the source of truth.

---

## Security notes

- The DeepSeek key is a Worker **secret**, never in `wrangler.toml`, never in the
  app, never in git.
- Session tokens are HS256 JWTs signed with `SESSION_SIGNING_SECRET`; the app gets
  one in exchange for a *verified* Apple identity token, so only real signed-in
  users get a session.
- `/admin/*` is gated by `ADMIN_SECRET`. Treat it like a password.
- The meter key is Apple's stable per-user `sub` (`credential.user` in the app) —
  reinstall-proof, so users can't reset their cap by reinstalling.
