# Pulse — Production Release RUNBOOK

Execute this document top-to-bottom to take Pulse from "builds on simulator" to "live on the App Store with the AI proxy on." Every step is grounded in the repo; ids, product-ids, secret-names, and line-refs are preserved verbatim. Do not invent values not listed here.

## 1. Release architecture overview

Pulse ships **no provider API keys in the binary** (grep confirms no `gsk_`/`sk-`/`AIza`/`sk-ant-` literals in `pulse/**.swift`). Instead, a **Cloudflare Worker proxy** (`pulse-ai-proxy`) holds the single provider key (`GEMINI_API_KEY`, for **Google Gemini** — model `gemini-2.5-flash-lite`) and meters spend against a global pot and per-user cap; the app authenticates to it with a Pulse-issued session JWT (60-day TTL) minted from the user's **Sign in with Apple** identity token. Data lives in **one CloudKit container** `iCloud.com.shimondeitel.pulsegoals` split two ways: a **private** database (`NSPersistentCloudKitContainer(name: "pulse")`) mirroring the full Core Data model per Apple-ID, and a **public** database holding exactly one world-readable record type `CommunityMember` for the community directory (no DMs ever in public). Pro features are gated behind a **single auto-renewable subscription** `com.shimondeitel.pulse.pro.monthly` (monthly, 1-week free trial). Debug builds target CloudKit **Development** and the legacy/Groq fallback path; **Release/App Store builds target CloudKit Production and the proxy** — but only once `ProxyConfig.baseURL` is set. The app degrades silently (local-only Core Data, empty community feed, proxy disabled) when these are not wired, so the blocking checklist below must be completed before any real user.

## 2. Prerequisites & accounts

- **Apple Developer Program** — Account Holder/Admin on team **W7Q885Q59C**. Required to register identifiers/capabilities, create the distribution cert, manage App Store Connect, and add testers. The app record for `com.shimondeitel.pulse` must already exist in App Store Connect.
- **Cloudflare** — account on the **Workers PAID plan ($5/mo)**. SQLite-backed Durable Objects (the `Ledger`) do **not** run on the free plan (README.md:50-53).
- **Google Gemini (AI provider)** — a **funded** Google AI / Gemini API account + production API key (`GEMINI_API_KEY`), default model `gemini-2.5-flash-lite`. The proxy caps spend, but the Gemini account must carry a balance (README.md:54-56). This is the only place real AI money is spent. *(A legacy `DEEPSEEK_API_KEY` secret may still exist but is now unused; the live key is `GEMINI_API_KEY` — index.js:206.)*
- **Groq (console access)** — required only to **revoke** the previously-shipped key at console.groq.com. No new Groq key is needed for production.
- **App Store Connect** — Paid Applications Agreement active + banking/tax forms complete (required for any IAP). For the CLI upload path: an App Store Connect API key (KEY_ID, ISSUER_ID, `.p8`) from Users and Access > Integrations.

---

## ⛔ BLOCKING before any real user — critical path

Do these **in order**. Each is release-blocking; skipping any one means real users hit silent failures (no AI, no cross-device sync, empty community, broken purchases, or a live leaked key).

1. **Revoke the leaked Groq key** — at console.groq.com > API Keys, delete/revoke the previously-shipped key. Treat it as compromised. (No `gsk_` literal remains in source; the only live Groq path is the transitional bridge `AIRouter.swift:88-92` → `GeminiDirectClient.swift:22` `https://api.groq.com/openai/v1/chat/completions`, keyed from Keychain `gemini_api_key`.) → details in §B / §F.

2. **Confirm proxy prerequisites** — Cloudflare Workers PAID plan active; **Google Gemini** account funded with a production key; `APPLE_BUNDLE_ID` in `wrangler.toml` equals `com.shimondeitel.pulse`. → §B.

3. **Deploy the Worker + set the three secrets** — from `ai-proxy/`: set `GEMINI_API_KEY`, `SESSION_SIGNING_SECRET`, `ADMIN_SECRET` via `wrangler secret put`, then `npm run deploy`. Capture the printed `https://pulse-ai-proxy.<subdomain>.workers.dev` URL. → §B.

4. **Set the proxy URL via the `PULSE_PROXY_BASE_URL` build setting** (no source edit needed). The URL is injected into the `PulseProxyBaseURL` Info.plist key at build time and read at runtime by `ProxyConfig.baseURL`. Provide it for the release archive — e.g. an `.xcconfig` line `PULSE_PROXY_BASE_URL = https://pulse-ai-proxy.<subdomain>.workers.dev`, or `xcodebuild … PULSE_PROXY_BASE_URL='https://…workers.dev'`. Empty (the committed default) = proxy off. Baked at build time → must be set **before** archiving. (Quick local test only: `ProxyConfig.overrideBaseURL` compile-time fallback — never commit a non-empty value.) → §B / §E.

5. **Resolve the HealthKit half-wired state** — code uses HealthKit + `NSHealthShare/UpdateUsageDescription` exist (pbxproj:399/400) but `pulse/pulse.entitlements` has **no** `com.apple.developer.healthkit` key. Either add the HealthKit capability + App ID capability, **or** cut HealthKit code + the two Info.plist Health keys + the xcprivacy Health/Fitness entries. Do not ship the middle state. → §F.

6. **Promote CloudKit schema Development → Production** — in CloudKit Dashboard for container `iCloud.com.shimondeitel.pulsegoals`: first generate the full Development schema (9 `CD_*` private types + public `CommunityMember`) by exercising a Debug build, ensure the `recordName` queryable index exists, then "Deploy Schema Changes…" to Production. Production starts empty; without this, private sync silently falls back to local-only and the community feed is empty. → §C.

7. **Create the IAP in App Store Connect** — auto-renewable subscription, Product ID **exactly** `com.shimondeitel.pulse.pro.monthly`, group `Pulse Pro`, 1-week free trial, and submit it attached to the 1.0 (build 1) version. Confirm Paid Applications Agreement is Active. → §D / §F.

8. **[BLOCKING] Reconcile the AI sub-processor disclosure (name Google)** — the production AI provider is **Google Gemini** (`GEMINI_API_KEY`, model `gemini-2.5-flash-lite` — index.js:136/206, wrangler.toml). The in-app Privacy Policy (`LegalViews.swift:222`), the App Store Privacy answers, and the public site (`website/privacy.html` §5) MUST all name **Google LLC (Gemini API)** as the sub-processor receiving chat content, roadmaps, translation, and user photos — not DeepSeek. Verify that no other direct client (Groq/Anthropic/DeepSeek) can receive user goal text or photos in a Release build (`AIRouter.swift`); if any can, disclose it too. Shipping with the disclosure naming the wrong vendor is a 5.1.1/5.1.2 rejection. → §F. → details in §F step 3.

Everything in the per-domain sections below either supports these steps or is standard (non-blocking) follow-through.

---

## A. Apple Developer — App IDs, capabilities, signing

Targets, all under team **W7Q885Q59C**, **Automatic** signing, `CODE_SIGN_IDENTITY = "Apple Development"`, empty `PROVISIONING_PROFILE_SPECIFIER`:
- App: `com.shimondeitel.pulse` — entitlements `pulse/pulse.entitlements` (pbxproj CODE_SIGN_ENTITLEMENTS :388/431).
- Widget: `com.shimondeitel.pulse.widgets` (plural) — WidgetKit app-extension embedded in `pulse.app`, entitlements `PulseWidget/PulseWidget.entitlements` (pbxproj :679/709).

Deployment target iOS 26.5; MARKETING_VERSION 1.0; CURRENT_PROJECT_VERSION 1; Release is the default config.

> ⛔ Every step in this section is marked blocking in the source — all gate a signable distribution archive.

1. **[BLOCKING] Confirm the signing identity.** Open Xcode > Settings > Accounts and ensure the Apple ID tied to team **W7Q885Q59C** is signed in (DEVELOPMENT_TEAM at pbxproj lines 392, 435, 504, 568, 596, 618, 639, 659, 682, 711). Both shippable targets use `CODE_SIGN_STYLE = Automatic` (app :390/433, widget :680/710).

2. **[BLOCKING] Register the App Group first** (shared by both App IDs). developer.apple.com > Identifiers > (+) > App Groups, register exactly: `group.com.shimondeitel.pulsegoals` (required by `pulse.entitlements:17-20` and `PulseWidget/PulseWidget.entitlements`).

3. **[BLOCKING] Register the iCloud/CloudKit container.** Identifiers > (+) > iCloud Containers, register exactly: `iCloud.com.shimondeitel.pulsegoals` (literal `iCloud.` prefix, NOT the bundle id; `pulse.entitlements:9-12`). Only the main app uses iCloud.

4. **[BLOCKING] Register the main App ID `com.shimondeitel.pulse`** and toggle ON exactly three capabilities: (1) **Sign In with Apple** (leave as primary/Default to match `pulse.entitlements:5-8`); (2) **iCloud** → "Include CloudKit support" → assign `iCloud.com.shimondeitel.pulsegoals`; (3) **App Groups** → assign `group.com.shimondeitel.pulsegoals`. Do **NOT** enable HealthKit, Camera, Face ID, or Photo Library here — those are Info.plist usage strings (pbxproj:397-402, 440-445), not signed capabilities, and extra capabilities make the generated profile mismatch the entitlements file. *(See §F step 1 — if HealthKit ships in 1.0, the HealthKit capability is added here and in the entitlements.)*

5. **[BLOCKING] Register the widget App ID `com.shimondeitel.pulse.widgets`** (plural) and toggle ON **only App Groups** → `group.com.shimondeitel.pulsegoals`. Do **NOT** enable iCloud or Sign In with Apple — the widget entitlements declare only the App Group; extras break the widget profile. The widget needs its own App ID and own provisioning profile.

6. **[BLOCKING] Decide automatic vs manual distribution signing.** RECOMMENDED (automatic): in Xcode select the `pulse` target > Signing & Capabilities > Release > "Automatically manage signing", Team = W7Q885Q59C; Xcode creates the Apple Distribution cert and an "iOS App Store" profile for `com.shimondeitel.pulse`, then repeat for `PulseWidgetExtension` (own managed profile for `com.shimondeitel.pulse.widgets`). Requires steps 4–5 done first. ALTERNATIVE (manual): create an Apple Distribution cert + two App Store profiles (one per App ID), set `CODE_SIGN_STYLE = Manual` and matching `PROVISIONING_PROFILE_SPECIFIER` per target.

7. **[BLOCKING] Verify Signing & Capabilities matches the committed entitlements** (no extras, no missing). `pulse` target must show: Sign In with Apple; iCloud with CloudKit checked + container `iCloud.com.shimondeitel.pulsegoals`; App Groups with `group.com.shimondeitel.pulsegoals`; CODE_SIGN_ENTITLEMENTS still → `pulse/pulse.entitlements`. `PulseWidgetExtension` must show only App Groups `group.com.shimondeitel.pulsegoals`; CODE_SIGN_ENTITLEMENTS still → `PulseWidget/PulseWidget.entitlements`. Remove any extra capability row; revert any key Xcode added that the committed file lacks (the committed files are authoritative for CloudKit/CI).

8. **[BLOCKING] Confirm the Distribution certificate exists** for team W7Q885Q59C with its private key in your login keychain (Xcode > Settings > Accounts > Manage Certificates can create it). Both targets are signed by the same distribution cert; only the profiles differ.

9. **[BLOCKING] Produce and validate a signed distribution archive** against Release:
   ```bash
   xcodebuild -project /tmp/pulse_local/pulse.xcodeproj \
     -scheme pulse -configuration Release \
     -archivePath /tmp/pulse_local/build/Pulse.xcarchive archive
   ```
   Export with an App Store export options plist, then verify embedded entitlements:
   ```bash
   codesign -d --entitlements :- <path-to-pulse.app>
   ```
   Confirm the app lists `com.apple.developer.applesignin`, `com.apple.developer.icloud-container-identifiers` (`iCloud.com.shimondeitel.pulsegoals`), `com.apple.developer.icloud-services` (`CloudKit`), and `com.apple.security.application-groups` (`group.com.shimondeitel.pulsegoals`). Run the same check on the embedded `PulseWidgetExtension.appex` and confirm it lists **only** the App Group.

---

## B. Cloudflare Worker proxy — deploy, secrets, key rotation

Worker `pulse-ai-proxy` (`wrangler.toml:1`), entry `src/index.js`, `compatibility_date 2024-11-01`, `nodejs_compat`. Deploy = `npm run deploy` → `wrangler deploy` (package.json:9); syntax gate `npm run check` (package.json:12); only dep is `wrangler ^3.90.0`. All commands run from `ai-proxy/` (cwd `/tmp/pulse_local/ai-proxy`).

1. **[BLOCKING] Prerequisites (operator account actions).** (a) Cloudflare Workers **PAID** plan ($5/mo) — required for the SQLite Durable Object `Ledger` (README.md:50-53). (b) Funded **Google Gemini** account + API key (`GEMINI_API_KEY`) (README.md:54-56). (c) Apple bundle id for Sign in with Apple matches the proxy's `APPLE_BUNDLE_ID` (`com.shimondeitel.pulse`).

2. **[BLOCKING] Install toolchain and authenticate.**
   ```bash
   cd <repo>/ai-proxy
   npm install
   npx wrangler login        # opens a browser; authorize it
   npx wrangler whoami       # sanity-check account/subdomain
   ```

3. **[BLOCKING] Set the THREE Worker secrets** (exact names, confirmed against `index.js` env reads):
   - `GEMINI_API_KEY` — index.js:206 (guard, "no Gemini key"), :136 (`Bearer ${env.GEMINI_API_KEY}`). Your funded **Google Gemini** key. *(A legacy `DEEPSEEK_API_KEY` secret is now unused — index.js no longer reads it.)*
   - `SESSION_SIGNING_SECRET` — index.js:152/156/178/198. HS256 signer for the 60-day session JWT. 32+ bytes.
   - `ADMIN_SECRET` — index.js:420/425. Bearer/`x-admin-secret` gate for `/admin/*`.

   Generate the two random secrets locally (different values; store `ADMIN_SECRET` in a password manager — never recoverable):
   ```bash
   openssl rand -base64 48    # -> SESSION_SIGNING_SECRET
   openssl rand -base64 48    # -> ADMIN_SECRET
   ```
   Set them:
   ```bash
   printf %s '<YOUR_FUNDED_GEMINI_KEY>'          | npx wrangler secret put GEMINI_API_KEY
   printf %s '<SESSION_SIGNING_SECRET_FROM_OPENSSL>' | npx wrangler secret put SESSION_SIGNING_SECRET
   printf %s '<ADMIN_SECRET_FROM_OPENSSL>'       | npx wrangler secret put ADMIN_SECRET
   npx wrangler secret list   # verify all three exist (values never shown)
   ```
   Keep `SESSION_SIGNING_SECRET` stable — rotating it just forces apps to re-exchange via `/v1/session`, no data loss (README.md:87-88).

4. **[BLOCKING] Confirm the `[vars]` match the app** (`wrangler.toml:23-31`, baked in at deploy). Edit `wrangler.toml` then redeploy only if wrong.
   - `APPLE_BUNDLE_ID = "com.shimondeitel.pulse"` (wrangler.toml:26) — **MUST** equal the app bundle id; it is the required `aud` when verifying the Apple token (index.js:148). A mismatch silently kills **every** `/v1/session` and all AI. *(README.md:100 shows a stale `com.shimon.pulse` — trust the toml.)*
   - `PER_USER_CAP_USD = "2.75"` (consumed index.js:173/323).
   - `POT_TOTAL_USD = "100"` — global ceiling; only **seeds on the very first deploy**, afterward the stored value wins (README.md:104-107). Change a running pot via `/admin/topup`, not here.
   - `MAX_OUTPUT_TOKENS = "16384"` (clamps max_tokens, index.js:214-215).
   - `UPSTREAM_MODEL = "gemini-2.5-flash-lite"` (wrangler.toml; index.js:243 `DEFAULT_UPSTREAM_MODEL`) — the real Google Gemini model every request is forwarded to and priced by. Swap to `gemini-2.5-flash` for higher quality at ~6× the cost.
   - `ALLOWED_MODELS = "deepseek-v4-pro,deepseek-v4-flash,gemini-2.5-flash-lite,gemini-2.5-flash"` (index.js:233 `isAllowedModel`) — names a caller MAY request. The legacy `deepseek-v4-*` names are kept only so installed app builds still validate; the proxy maps them onto `UPSTREAM_MODEL` (Gemini) and prices by it.
   - `RATE_LIMIT_PER_MIN = "30"`, `MAX_MESSAGES = "200"`, `MAX_PROMPT_BYTES = "262144"`.

5. **[standard] Durable Object / Ledger migration — applied automatically on deploy.** `wrangler.toml:41-47` declares binding `LEDGER` → class `Ledger` and migration tag `v1` `new_sqlite_classes=["Ledger"]`; class exported at index.js:6; singleton `idFromName("global")` (index.js:105). No separate command. **Never** edit/rename/duplicate tag `v1` (orphans the pot/meter state) — if you ever change the `Ledger` class, add a NEW migration tag.

6. **[BLOCKING] Deploy the Worker and capture the URL.**
   ```bash
   npm run check     # optional fast syntax gate (package.json:12)
   npm run deploy    # -> wrangler deploy (package.json:9)
   ```
   Wrangler prints e.g. `https://pulse-ai-proxy.<subdomain>.workers.dev` (README.md:115). **COPY THIS URL** — it goes into ProxyConfig (step 8). The subdomain is not knowable until first deploy.

7. **[standard] Smoke-test the deployed Worker before touching the app.**
   ```bash
   BASE="https://pulse-ai-proxy.<subdomain>.workers.dev"
   ADMIN="<your ADMIN_SECRET>"
   curl -s "$BASE/health"                                          # liveness (index.js:16)
   curl -s "$BASE/admin/status" -H "x-admin-secret: $ADMIN"
   # expect: {"potTotal":100,"potSpent":0,"potRemaining":100,"activeReservations":0}
   ```
   Raise the ceiling later without redeploy (index.js:354-365):
   ```bash
   curl -s -X POST "$BASE/admin/topup" -H "x-admin-secret: $ADMIN" \
     -H "content-type: application/json" -d '{"amountUSD": 50}'
   ```
   A 401 = `ADMIN_SECRET` mismatch; a 500 "server misconfigured" on `/v1/*` = a secret is missing (re-check step 3).

8. **[BLOCKING] APP-SIDE ACTION #1: set the `PULSE_PROXY_BASE_URL` build setting** to the deployed URL (step 6), **no trailing slash, no source edit**. The value is injected into the `PulseProxyBaseURL` Info.plist key (`pulse/Info.plist`) at build time and read at runtime by `ProxyConfig.baseURL`. Set it via an `.xcconfig`, the target build settings, or the command line:
   ```sh
   # .xcconfig
   PULSE_PROXY_BASE_URL = https://pulse-ai-proxy.<subdomain>.workers.dev
   # or one-off:
   xcodebuild archive … PULSE_PROXY_BASE_URL='https://pulse-ai-proxy.<subdomain>.workers.dev'
   ```
   Keeping the deploy URL in build config (not committed source) is intentional — the file that previously leaked a key stays free of deploy-time values. A non-empty resolved `baseURL` flips `ProxyConfig.isEnabled` true (ProxyConfig.swift:22-24), which (a) routes `/v1/session`, `/v1/chat`, `/v1/budget` through the Worker (ProxyConfig.swift:33-39), (b) skips the bypassable device daily gate so the server's 429 `user_cap` is the source of truth (AIRouter.swift:111), (c) switches model selection to monthly-cap logic — Flash after ~85% of budget (AIRouter.swift:123-131), (d) stops the transitional Groq bridge from ever being called (AIRouter.swift:88-92,164). Rebuild and ship with this value committed. While `baseURL` stays `""`, the app uses the legacy/Groq path.

9. **[BLOCKING] APP-SIDE ACTION #2: revoke/rotate the live Groq key.** This is a **Groq-console action**, not a code edit (no `gsk_` literal remains in source). Log in at console.groq.com > API Keys and delete/revoke the exposed key — treat any previously-shipped build's key as compromised. Safe because once step 8 sets `baseURL`, `ProxyConfig.isEnabled` short-circuits the bridge (AIRouter.swift:111). For stale keys provisioned on a device's Keychain (`KeychainKey.geminiAPIKey = "gemini_api_key"`), `removeAPIKey()` / `KeychainManager delete(.geminiAPIKey)` exists (GeminiDirectClient.swift:63-64), but the server-side Groq revoke is authoritative.

10. **[standard] Post-cutover verification.** On a build with `baseURL` set: sign in with Apple, trigger an AI action, then:
    ```bash
    curl -s "$BASE/admin/status" -H "x-admin-secret: $ADMIN"   # potSpent should now be > 0
    npx wrangler tail                                          # live logs (package.json:11)
    ```
    Error contract the app keys off (README.md:163-167): `429 user_cap` → limit modal; `402 pot_exhausted` → top up (step 7); `401 unauthorized` → app re-exchanges session.

> **Pricing lockstep:** `src/pricing.js` always prices the real upstream **Google Gemini** model `gemini-2.5-flash-lite` (rates pricing.js:15-23; the legacy `deepseek-v4-*` entries are never billed because the proxy always prices `UPSTREAM_MODEL`). Keep `UPSTREAM_MODEL` and its `PRICING` entry matched or the Worker fatals on a missing-price config (index.js:250) and the budget meter drifts (README.md:189-194).

---

## C. CloudKit schema → Production deploy

One container `iCloud.com.shimondeitel.pulsegoals` (PersistenceController.swift:79), two databases:
- **Private** — `NSPersistentCloudKitContainer(name: "pulse")` (PersistenceController.swift:97); the full Core Data model flagged `usedWithCloudKit="YES"`. 9 entities → `CD_`-prefixed record types: Achievement, DailyTask, FocusSession, Goal, MentorMessage, Milestone, NotificationRecord, ProgressEntry, UserProfile.
- **Public** — `container.publicCloudDatabase` (CloudKitCommunityService.swift:40); ONE record type `CommunityMember` (CloudKitCommunityService.swift:33). Grep confirms no other `publicCloudDatabase`/`CKShare`/`sharedCloudDatabase` usage.

`CommunityMember` fields WRITTEN by `publishProfile` (CloudKitCommunityService.swift:87-95): `name`, `level`, `totalXP`, `currentStreak`, `longestStreak`, `goalsCompleted`, `activeGoals`, `lastActive` (Date), `topCategories` (String list). Record ID = user's `userRecordID().recordName`, upserted `.allKeys` (one per user). Fields READ but never written: `location` (line 140), `bio` (line 147) — optional, do not block on them. Entitlements have no `icloud-container-environment` key, so **Debug → Development, Release → Production**.

1. **[standard]** Understand the two stores (read-only context — see above).
2. **[standard]** Enumerate the exact `CommunityMember` fields the runbook must guarantee exist in Production (the 9 written fields above; `location`/`bio` not required).
3. **[BLOCKING] Generate the full Development schema by exercising a Debug build.** Production can only be promoted from Development. On a Debug build (targets Development by default): (1) sign the device/simulator into iCloud; (2) complete onboarding so a `UserProfile` + at least one Goal/Milestone/DailyTask are created — this materializes every `CD_*` private type; (3) set community visibility to a **non-private** value and trigger a publish so `publishProfile` creates `CommunityMember` with all fields (it early-returns/deletes if visibility == `.privateOnly`, lines 53-56); (4) in CloudKit Dashboard → Development → Schema, confirm all 9 `CD_*` types **and** `CommunityMember` (with all 9 fields) are present.
4. **[BLOCKING] Add the queryable index the public fetch requires (Development).** `fetchCommunityMembers` runs `CKQuery(recordType: "CommunityMember", predicate: NSPredicate(value: true))` (line 126) — a fetch-all that requires the system `recordName` field to be **QUERYABLE** or it throws (swallowed into an empty feed, lines 156-159). Sorting/presence is in-memory (lines 133-134, 152-155) — no custom SORT/FILTER index needed. In CloudKit Dashboard → Development → Schema → Indexes for `CommunityMember`, add a QUERYABLE index on `recordName` (CloudKit usually adds it on API-created types — verify it).
5. **[BLOCKING] Promote Development → Production.** Single most important pre-release action — an App Store build targets Production CloudKit, which starts EMPTY; without promotion private sync silently falls to local-only (PersistenceController.swift:130-138) and the community feed is empty (CloudKitCommunityService.swift:156-159). Steps:
   1. https://icloud.developer.apple.com/dashboard → select container `iCloud.com.shimondeitel.pulsegoals`.
   2. Confirm you're in DEVELOPMENT and Schema shows all 9 `CD_*` + `CommunityMember` + the `recordName` queryable index.
   3. Click "Deploy Schema Changes…"; review the diff (confirm `CommunityMember` and its fields are in it).
   4. Click Deploy (schema only — does NOT copy Development records).
   5. Switch the selector to PRODUCTION and verify all `CD_*` types, `CommunityMember` with all 9 written fields, and the `recordName` queryable index are present. Promotion is additive/non-destructive, so deploying early is safe.
6. **[BLOCKING] Verify against Production with a Release-config build before submitting.** (1) Build in Release (TestFlight or Release-signed device) — this targets Production CloudKit. (2) Sign into iCloud, onboard, create a goal → confirm `[Persistence] CloudKit store load failed` (line 138) does **NOT** appear and data syncs to a second device on the same Apple ID. (3) Set visibility to non-private, publish, open Community → confirm members load. An empty feed + `[Community] fetchCommunityMembers failed` (line 157) means promotion didn't take — go back to step 5.
7. **[BLOCKING] (privacy guarantee) Confirm no private/DM data is in the public DB and keep it that way.** Hard rule: DMs/private data must NEVER hit the world-readable public DB. Code currently honors this: `sendMessage(...)` (lines 174-176) and `fetchMessages(...)` (lines 181-183) are no-op stubs; only non-sensitive `CommunityMember` fields are written (lines 87-95); streak/level/XP are zeroed when "Show Activity" is off (lines 72-79); a Private account is removed from the directory (lines 53-56, 104-112). Gate: before any release, grep `publicCloudDatabase`/`publicDB` and confirm matches stay confined to `CloudKitCommunityService` writing only the `CommunityMember` fields above. Any future real DMs MUST use a private zone / CKShare / authenticated endpoint and a NEW private record type (per the SECURITY header lines 14-18) — never the public `CommunityMember` schema.

---

## D. StoreKit / App Store Connect IAP

Single product, ID **`com.shimondeitel.pulse.pro.monthly`** — `StoreManager.swift:28` and `Pulse.storekit:105`. The only product the app fetches (`Product.products(for: [Self.proProductID])`, StoreManager.swift:113). Type: auto-renewable subscription (`"RecurringSubscription"`, Pulse.storekit:109); billing monthly `P1M`; group `Pulse Pro`; reference name `Pulse Pro Monthly`; 1-week free intro trial (`P1W`, paymentMode free, Pulse.storekit:93-97); Family Sharing OFF. Display name `Pulse Pro`; description `Unlock every AI feature: AI-built plans and pulses, the AI coach, meal and form analysis, and unlimited goals.` (Pulse.storekit:98-104). Owner bundle id: `com.shimondeitel.pulse`. Local test file: `/tmp/pulse_local/Pulse.storekit`.

1. **[BLOCKING] Confirm what the code expects (read-only).** Product id `com.shimondeitel.pulse.pro.monthly` must match App Store Connect **character-for-character** or `loadProducts()` returns empty, `proProduct` stays nil, and `purchase()` fails with `productUnavailable` (StoreManager.swift:127-130). Subscription-only APIs are used: `Transaction.currentEntitlements` (:181), `proProduct?.subscription` (:57, :206), `sub.status` (:211), `Transaction.updates` (:229).
2. **[BLOCKING] Create the auto-renewable subscription in App Store Connect.** App > Monetization > Subscriptions. (1) Create a Subscription Group, reference name `Pulse Pro`. The GUIDs in the `.storekit` file (group `BABDBEBF-95C3-4B5D-967C-41C20D23D695`, product internalID `B12CE639-…`) are LOCAL-ONLY — App Store Connect generates its own; only the product-id string must match. (2) Create the subscription with Product ID exactly `com.shimondeitel.pulse.pro.monthly` (immutable once saved). (3) Reference Name `Pulse Pro Monthly`. (4) Duration 1 Month.
3. **[BLOCKING] Set the price = US $9.99.** No mismatch to resolve: `Pulse.storekit:89` (`"displayPrice":"9.99"`), the in-code fallback (`StoreManager.swift:57`, `?? "$9.99"`), and the paywall copy all agree on **$9.99/mo**. At runtime the price always comes from App Store Connect (StoreManager.swift:57 prefers `proProduct.displayPrice`); the `.storekit` 9.99 only affects local Xcode testing. Set the **US $9.99** tier in App Store Connect.
4. **[standard] Add the free-trial introductory offer.** On the subscription: Introductory Offer > Free Trial > 1 Week > Eligibility: New subscribers. Read at `StoreManager.swift:217` (`isInTrialPeriod = (transaction.offer?.type == .introductory)`). Shipping without it just hides the trial badge (no crash) but diverges from the local config and marketing promise.
5. **[BLOCKING] Fill required metadata and localization** (en_US, from Pulse.storekit:98-104): Display Name `Pulse Pro`; Description `Unlock every AI feature: AI-built plans and pulses, the AI coach, meal and form analysis, and unlimited goals.` Set `familyShareable` = OFF. Upload the subscription review screenshot + review note. Missing localization or screenshot blocks submission.
6. **[BLOCKING] Complete the paid-apps agreement + banking/tax.** App Store Connect > Business / Agreements must be **Active** with banking + tax forms complete, or the subscription can't be approved and `Product.products(for:)` returns nothing in production even when the product exists.
7. **[BLOCKING] Attach the subscription to the app version and submit for review.** In the version's Subscriptions section, select `com.shimondeitel.pulse.pro.monthly` so it is reviewed alongside the 1.0 (build 1) submission. A first-ever subscription submitted separately commonly stalls in "Waiting for Review" / "Developer Action Needed."
8. **[BLOCKING] Testing + RELEASE GATE on the StoreKit config.** Two paths:
   - **Local:** Xcode scheme > Run > Options > StoreKit Configuration = `Pulse.storekit`. Note `_failTransactionsEnabled=false` and all `_storeKitErrors` disabled (Pulse.storekit:22,26-72) — happy-path only; flip them on temporarily to exercise the `failedVerification`/`productUnavailable` branches (StoreManager.swift:88-92, 127-130).
   - **Sandbox:** scheme StoreKit Configuration = **None**, install on a device signed into a Sandbox tester; verify the live product loads, the 1-week trial applies, renewal state resolves (`refreshRenewalState`, :205-223), and restore works (:165-171).
   - **RELEASE GATE:** the Release/Archive scheme MUST have **StoreKit Configuration = None**. If `Pulse.storekit` is left selected for the archive, the app talks to the local fake store and real purchases never resolve.
9. **[standard] Post-setup verification against the entitlement code.** A successful `purchase()` finishes the transaction and calls `refreshEntitlements()` (:141-144), which sets `isPro` only for a verified, non-revoked, non-expired transaction matching `Self.proProductID` (:181-190), then calls `SubscriptionManager.shared.applyEntitlement(...)` (:196-201) — this is what flips AI access on. Verify a sandbox refund/cancel re-locks Pro (revocationDate/expirationDate branches, :184-185). If `isPro` never becomes true after a sandbox purchase, suspect a product-id mismatch from step 2.

---

## E. TestFlight — archive, upload, internal testing

Shared scheme `pulse.xcscheme` (ArchiveAction uses Release, `buildForArchiving=YES`, `revealArchiveInOrganizer=YES`). App Release `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` → dSYMs generated; `VALIDATE_PRODUCT = YES`. Widget Release `SKIP_INSTALL = YES` (correct for an embedded extension). `PrivacyInfo.xcprivacy` present at `/tmp/pulse_local/pulse/PrivacyInfo.xcprivacy`. `pulse/Info.plist` is an empty `<dict/>`; `ITSAppUsesNonExemptEncryption` absent project-wide. No `ExportOptions.plist` in the repo.

1. **[BLOCKING] Pre-flight gates (before archiving).** (a) **AI proxy off** — the `PULSE_PROXY_BASE_URL` build setting (empty by default); production AI only turns on when set to the deployed Worker URL (form `https://pulse-ai-proxy.<subdomain>.workers.dev`). Compile-time baked → cannot change after archive. Either deploy the Worker and paste the URL (§B step 8), or knowingly ship with proxy AI disabled. (b) **Revoke the Groq key** in the Groq console (§B step 9). Also confirm `wrangler.toml` `APPLE_BUNDLE_ID = "com.shimondeitel.pulse"` matches the app bundle id (pbxproj:456) or sign-in breaks once the proxy is live.
2. **[BLOCKING] Confirm signing, team, shared scheme.** Automatic signing, DEVELOPMENT_TEAM = W7Q885Q59C; in Xcode ensure "Automatically manage signing" is checked with Team = W7Q885Q59C on **both** the `pulse` and `PulseWidgetExtension` targets; you must be signed into an account on team W7Q885Q59C with App Manager/Admin rights. Scheme `pulse` is already shared (ArchiveAction = Release); no scheme changes required. Capabilities needing matching portal App IDs/containers: Sign in with Apple, CloudKit container `iCloud.com.shimondeitel.pulsegoals`, App Group `group.com.shimondeitel.pulsegoals` (widget shares the group).
3. **[BLOCKING] Bump the build number — APP and WIDGET together.** Version values are duplicated per target in `project.pbxproj` (NOT shared via xcconfig): app `pulse` (Release :455 MARKETING_VERSION, :434 CURRENT_PROJECT_VERSION) and `PulseWidgetExtension` (Release :722/:711). App Store validation fails if the embedded extension's version/build differ from the host. The first upload can go as `1.0 (1)`; every subsequent upload MUST raise the build number.
   ```bash
   xcrun agvtool new-version -all 2          # sets CURRENT_PROJECT_VERSION on all targets
   xcrun agvtool new-marketing-version 1.0   # only if changing marketing version
   xcrun agvtool what-version
   xcrun agvtool what-marketing-version
   ```
   Bump `CURRENT_PROJECT_VERSION` on every single upload (1 → 2 → 3 …) even within 1.0; keep app and widget identical. (Test targets at :595/:599, :617/:621, :638/:641, :659/:661 don't ship — ignore.)
4. **[standard] Archive via Xcode UI.** Open `/tmp/pulse_local/pulse.xcodeproj`, pick the `pulse` scheme, set destination to "Any iOS Device (arm64)", then Product > Archive (builds Release, embeds `PulseWidgetExtension.appex`). Keep the dSYMs. The scheme's `Pulse.storekit` reference affects local debug runs only, not the archive or live IAP.
5. **[standard] Archive via CLI (alternative).**
   ```bash
   xcodebuild -project pulse.xcodeproj \
     -scheme pulse -configuration Release \
     -destination 'generic/platform=iOS' \
     -archivePath "$HOME/Desktop/Pulse-1.0-$(xcrun agvtool what-version -terse).xcarchive" \
     clean archive
   ```
   If a CI machine isn't logged into the team, add: `DEVELOPMENT_TEAM=W7Q885Q59C -allowProvisioningUpdates`.
6. **[BLOCKING] Validate + distribute via Xcode Organizer.** Window > Organizer > Archives → select the archive. (1) "Validate App" → App Store Connect, automatic signing, upload symbols = Yes (re-checks signing, embedded-widget version match, and PrivacyInfo presence). Fix any issue. (2) "Distribute App" > App Store Connect > Upload (team W7Q885Q59C). (3) Build shows under TestFlight > iOS as "Processing" (minutes to ~1 hour).
7. **[standard] Validate + upload via CLI (alternative).** Author an `ExportOptions.plist` (none in repo): `method = app-store-connect` (older Xcode `app-store`), `teamID = W7Q885Q59C`, `signingStyle = automatic`, `uploadSymbols = true`, `destination = export`. Then:
   ```bash
   xcodebuild -exportArchive \
     -archivePath "$HOME/Desktop/Pulse-...xcarchive" \
     -exportOptionsPlist ExportOptions.plist \
     -exportPath "$HOME/Desktop/PulseExport" \
     -allowProvisioningUpdates
   xcrun altool --validate-app -f "$HOME/Desktop/PulseExport/pulse.ipa" -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
   xcrun altool --upload-app   -f "$HOME/Desktop/PulseExport/pulse.ipa" -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
   ```
   (`altool` reads the `.p8` from `~/.appstoreconnect/private_keys/`; KEY_ID/ISSUER_ID from App Store Connect > Users and Access > Integrations — not in the repo.) Or set `method=app-store` to let `xcodebuild -exportArchive` upload directly.
8. **[standard] Privacy manifest — present, no action.** `PrivacyInfo.xcprivacy` is bundled into the `pulse` target (NSPrivacyTracking=false; required-reason APIs UserDefaults CA92.1, FileTimestamp C617.1). Just ensure App Store Connect > App Privacy answers match it. (Widget has no manifest of its own — add one to `PulseWidget/` only if validation flags the appex.)
9. **[BLOCKING] Export compliance — answer the encryption prompt.** `ITSAppUsesNonExemptEncryption` is absent and `pulse/Info.plist` is an empty `<dict/>`, so the prompt appears. The app uses only HTTPS/TLS (no custom crypto) → standard exemption. Answer: "Does your app use encryption?" → **Yes**; "Does it qualify for an exemption?" → **Yes** (standard encryption/HTTPS, the (b)/(d) exemption). No ERN required. To stop being asked every upload, add to `pulse/Info.plist`:
   ```xml
   <key>ITSAppUsesNonExemptEncryption</key><false/>
   ```
10. **[standard] TestFlight processing + internal testing.** In App Store Connect for `com.shimondeitel.pulse`: (1) wait for the build to leave "Processing." (2) Internal testing needs **no** Beta App Review — TestFlight > Internal Testing > create a group, add testers (must be Users in Users and Access on team W7Q885Q59C; up to 100 internal). (3) Assign the build; optionally "Automatically distribute new builds." (4) Caveat: if PULSE_PROXY_BASE_URL is unset, internal testers won't exercise production proxy-AI — deploy the Worker and re-archive with `baseURL` set first if they need to validate live AI. (External testing requires Beta App Review — out of scope for internal.)

---

## F. Pre-submission review checklist

1. **[BLOCKING] HealthKit: add the entitlement+capability, or strip it.** `pulse/pulse.entitlements` has **no** `com.apple.developer.healthkit` key, yet HealthKit is used (`Services/HealthKitManager.swift`; `Views/GoalDetail/TransformationDetailView.swift`, `GoalDetailRouter.swift`) and Info.plist declares `NSHealthShareUsageDescription` (pbxproj:399) + `NSHealthUpdateUsageDescription` (pbxproj:400). FIX (ship it): add the HealthKit capability to the `pulse` target (adds `com.apple.developer.healthkit`, plus `com.apple.developer.healthkit.access` if you write data) and enable HealthKit on the App ID. FIX (cut it): delete the HealthKit code paths, remove the two `INFOPLIST_KEY_NSHealth*` lines, and remove `NSPrivacyCollectedDataTypeHealth`/`Fitness` from `PrivacyInfo.xcprivacy:49,61`. Do not ship the half-wired state.
2. **[BLOCKING] Turn on the AI proxy and revoke the Groq key.** the `PULSE_PROXY_BASE_URL` build setting (empty by default) → proxy disabled, falls back to Groq-direct (`GeminiDirectClient.swift:22`). (1) Deploy the Worker:
   ```bash
   cd /tmp/pulse_local/ai-proxy && npx wrangler secret put GEMINI_API_KEY && \
   npx wrangler secret put SESSION_SIGNING_SECRET && npx wrangler secret put ADMIN_SECRET && npm run deploy
   ```
   (2) Set PULSE_PROXY_BASE_URL to the deployed URL (no trailing slash). (3) Rebuild and confirm AI calls carry only the Pulse session JWT. Then **revoke** the previously-embedded Groq key in the Groq console. (Cross-refs §B steps 6–9.)
3. **[BLOCKING] Reconcile the AI sub-processor disclosure (name Google).** The production AI provider is **Google Gemini** (`GEMINI_API_KEY`, model `gemini-2.5-flash-lite` — index.js:136/206). Update the Privacy Policy to name **Google Gemini (AI)** as the recipient of chat content, roadmaps, translation, and user photos: the in-app policy (`LegalViews.swift:222`) currently still names **DeepSeek** — change it to "Privacy Policy names Google Gemini (AI)" — and the public site (`website/privacy.html` §5) and the App Store Privacy answers must match. Then verify in `AIRouter.swift` that no other direct client (Groq/Anthropic/DeepSeek) can receive user goal text or photos in a Release build; if any can, disclose it too. Shipping an undisclosed or mis-named data recipient violates 5.1.1/5.1.2.
4. **[standard] Confirm the six usage strings render true** (pbxproj:397-402 / 440-445: Camera, FaceID, HealthShare, HealthUpdate, PhotoLibrary, PhotoLibraryAdd). Build, then `plutil -p` the generated Info.plist. Re-read the Camera string (pbxproj:397) — it claims video "is processed on your device and is never recorded or uploaded"; make sure that is literally true for the rep-counting/form feature (a false privacy claim is a rejection). Ensure the PhotoLibraryAdd string maps to an actual save-to-library path or remove it.
5. **[standard] Verify the privacy manifest matches real data flows.** Declares EmailAddress, Name, UserID, Health, Fitness, PhotosorVideos, OtherUserContent, ProductInteraction (Linked, AppFunctionality), CrashData; NSPrivacyTracking=false; API reasons UserDefaults CA92.1 (:127) + FileTimestamp C617.1 (:135). (a) If HealthKit is cut, remove Health (:49) + Fitness (:61). (b) Confirm CrashData is actually collected (Privacy Policy s19 says no analytics SDKs). (c) `ProductInteraction` implies usage analytics — confirm a source or drop it to stay consistent with the "no analytics" claim.
6. **[BLOCKING] App Privacy "Data Collection" answers in App Store Connect.** Goal titles/descriptions/notes/coach-chat and photos are transmitted to the AI provider (`LegalViews.swift:188`, Privacy s2 lines 184-193) → Data Collected = **Yes**. Map: User Content → Other User Content (goals, notes, chat) + Photos or Videos; Identifiers → User ID + Email Address + Name (Sign in with Apple); Diagnostics → Crash Data; Usage Data → Product Interaction (only if step 5 keeps it); Health & Fitness (only if HealthKit ships). For every type: Used for App Functionality, Linked to identity = Yes, Used for Tracking = No. Declare data sent to a third party (AI provider) but not sold/shared for advertising. Answers must match `PrivacyInfo.xcprivacy` exactly.
7. **[standard] Sign in with Apple — verify it is the primary/only login (4.8/5.1.1).** Entitlement present (`pulse.entitlements:5-7`); `AuthService.swift` is Apple-only. Confirm `Views/Auth/AuthWelcomeView.swift` uses the standard `ASAuthorizationAppleIDButton`, requests name/email scopes, handles "Hide My Email" relay, and handles credential-state revocation (`AuthService.swift:137 getCredentialState`) so a user who removes the app from their Apple ID is signed out.
8. **[standard] REVIEW RISK — account-deletion token revocation (5.1.1(v)).** In-app delete exists and erases data (`ProfileView.swift:301` → `AuthManager.deleteAccount`, `AuthService.swift:234`), satisfying the core requirement. But `AuthService.swift:230-233` notes it does NOT call Apple's server-side token-revocation endpoint (no backend holds the Apple client secret). Decide: (a) accept the risk and explain in App Review notes that deletion fully erases all data and the app runs no token-holding server, or (b) add a revocation call (the ai-proxy Worker could host `/v1/apple-revoke` using the Apple client secret). Add a reviewer-notes paragraph regardless.
9. **[BLOCKING] UGC 1.2 — wire post-level Report to real moderation.** User-level block/report exist (`CommunityModerationService.swift`; `CommunityPreferencesView.swift:207`; inline `ModerationMenu` in `CommunityChat.swift:174`, `MemberProfileView.swift:197`, `StoryViewer.swift:188`) and content is filtered (`ContentFilter.masked`, `PostCardView.swift`; abusive chat blocked `CommunityChat.swift:203`). **GAP:** the per-post "Report" (`PostCardView.swift:70`) just calls `store.deletePost(post.id)` — identical to "Hide this post" (line 67) — so it doesn't flag to moderation or block the author. FIX: route `PostCardView` Report through `CommunityModerationService.report(...)` and offer block-author from the same menu. Also confirm Terms s9 (`LegalViews.swift:60`) is the displayed EULA. Apple specifically tests reporting flows — treat as blocking.
10. **[standard] Health/AI disclaimers surfaced in-context.** Disclaimers exist in Terms s4 (AI not advice, `LegalViews.swift:40`), s7 (health, :52), s8 (photo/biometric, :56), Privacy s6/s20. Verify a visible "informational only, not medical advice" line near the AI coach (`Views/Mentor/MentorChatView.swift`) and the transformation/photo feature (`TransformationDetailView.swift`), plus a first-run acknowledgement. Full legalese can stay in Settings.
11. **[BLOCKING] StoreKit subscription parity with App Store Connect (3.1.1/3.1.2).** `Pulse.storekit` defines `com.shimondeitel.pulse.pro.monthly`, $9.99/mo, 1-week free trial, group `Pulse Pro` (:89-113); `StoreManager.proProductID` matches (:28). (1) Create the IDENTICAL product id, price, and 1-week trial in App Store Connect (the `.storekit` is sandbox-only). (2) The empty top-level `products` array (Pulse.storekit:16) is fine for a pure subscription — verify the paywall (`Views/Settings/UpgradeView.swift`) loads via `Product.products(for:[proProductID])` and shows the StoreKit price, not a hardcoded value. (3) Ensure auto-renew disclosure + links to Terms (EULA) and Privacy on the paywall, plus a functional restore (`StoreManager.swift:163`). Provide a working sandbox/demo account in review notes.
12. **[standard] Reachability + final build sanity.** Align documented paths with real UI: Profile → Privacy (`ProfileView.swift:182`) and Profile → Delete Account (`ProfileView.swift:301`) must match Terms ("Profile → Privacy → Delete Account", `LegalViews.swift:81`) and Privacy ("Profile → Privacy", :263). Verify Terms and Privacy Policy are reachable in-app (`PrivacyPolicyView` shown `ProfileView.swift:248`) and the same URLs are entered in App Store Connect metadata. Bump build number before each upload. Confirm the widget app group equals `group.com.shimondeitel.pulsegoals`.

> Legal docs are present in-app, dated **Effective May 26, 2026 v2.0** (`TermsOfServiceView`/`PrivacyPolicyView`, `LegalViews.swift:20,171`); the Privacy Policy must name **Google Gemini (AI)** and Apple (iCloud/StoreKit/Sign in with Apple) as sub-processors. *(The in-app copy at `LegalViews.swift:222` still says DeepSeek — see §F step 3; the public `website/privacy.html` §5 has already been updated to "Google LLC (Gemini API)".)*

---

## Open items / decisions for the owner

**Account/portal actions that cannot be done from the repo**
- Apple Developer (team **W7Q885Q59C**, Admin): register App Group `group.com.shimondeitel.pulsegoals`, iCloud container `iCloud.com.shimondeitel.pulsegoals`, and both App IDs (`com.shimondeitel.pulse`, `com.shimondeitel.pulse.widgets`); confirm those identifiers aren't already taken under another team (globally unique); confirm a valid Apple Distribution cert + private key. No profiles/cert are committed.
- CloudKit Dashboard: a human must click "Deploy Schema Changes…" for container `iCloud.com.shimondeitel.pulsegoals`; visually verify the `CommunityMember` `recordName` index is QUERYABLE in Production after promote; verify all 9 `CD_*` entities materialized in Development before promoting; confirm public-DB Security Roles give "World" read but restrict write to the record creator (no repo artifact proves these).
- Cloudflare: confirm account is on the **Workers PAID** plan. Google Gemini: fund the account and obtain the production `GEMINI_API_KEY`. Generate `SESSION_SIGNING_SECRET` + `ADMIN_SECRET` and store `ADMIN_SECRET` in a password manager (never recoverable). Capture the actual `workers.dev` subdomain from `wrangler deploy` and set as PULSE_PROXY_BASE_URL.
- Groq: revoke the previously-shipped key at console.groq.com (treat as compromised).
- App Store Connect: confirm Paid Applications Agreement is **Active** + banking/tax complete; create the IAP and submit it attached to 1.0 (build 1); upload subscription review screenshot; enter Terms/Privacy URLs; complete App Privacy answers; set the age rating (Terms set 13+, `LegalViews.swift:33`); provide a sandbox/demo login + a Community test scenario in review notes. For CLI upload, obtain an App Store Connect API key (KEY_ID, ISSUER_ID, `.p8`).

**Product decisions**
- **HealthKit in 1.0?** Add entitlement + App ID capability (+ write-access key if logging workouts), OR cut it (remove code + 2 Info.plist Health keys + xcprivacy Health/Fitness). The repo is currently in a non-shippable middle state.
- **IAP price:** **$9.99** everywhere — `Pulse.storekit:89`, the `StoreManager.swift:57` fallback (`?? "$9.99"`), and the paywall all agree; no mismatch. Production price comes solely from App Store Connect — set the US $9.99 tier there.
- **Sign in with Apple token revocation (5.1.1(v)):** accept-and-document the no-backend stance, or add a revocation endpoint on the ai-proxy Worker using the Apple client secret.
- **`POT_TOTAL_USD`:** decide the final value before the first deploy (it only seeds once; afterward adjust only via `/admin/topup`).
- **Auto-distribute to the internal TestFlight group**, or assign builds manually?
- **Confirm `ProductInteraction`/`CrashData` are genuinely collected** — Privacy Policy s19 (`LegalViews.swift:323`) claims no analytics SDKs; drop `ProductInteraction` from `PrivacyInfo.xcprivacy` and the App Store answers if nothing collects usage analytics.

**Verification gates (require a device / Release build)**
- Sandbox: confirm the live product loads, the 1-week trial applies, and refund/cancel re-locks Pro (`StoreManager.swift:184-185`).
- Release build against Production CloudKit: confirm no `[Persistence] CloudKit store load failed`, cross-device sync works, and the Community feed loads (not `[Community] fetchCommunityMembers failed`).
- Confirm in `AIRouter.swift` which client serves production traffic once the proxy is enabled, and that no Anthropic/Gemini/Groq direct client can receive user goal text or photos in a Release build.
- Confirm the Release/Archive scheme has **StoreKit Configuration = None** (could not be verified from source — check in Xcode).