# PHASE 3 — App Store Connect: paste-ready metadata + click-list

App: **Pulse Goals** · `com.shimondeitel.pulse` · Apple ID **6774584500** · Team **W7Q885Q59C**
Subscription group **Pulse Pro** already exists (id 22129440).

---

## ✅ BLOCKER #1 — Subscription product-id mismatch — DONE (by Claude, live)
I already created the correctly-named subscription on your account:
- **Subscription id:** `6778478747` · **Product ID:** `com.shimondeitel.pulse.pro.monthly` (exact match to the app) · Reference Name `Pulse Pro Monthly` · 1 Month · Family Sharing off · in the **Pulse Pro** group.
- **English (U.S.) localization added:** Display Name `Pulse Pro`, Description `Unlock every AI feature and unlimited goals.` (ASC caps this field ~45 chars).
- The old mis-named **`PPROSUB10`** is still there, unused (Missing Metadata) — harmless; delete it whenever (I left it in place).

**⏳ Remaining on this subscription (~3 web-UI clicks — the API flow for these isn't reliable):**
1. **Pricing → Add** → United States **$9.99** → let ASC auto-fill worldwide → Confirm.
2. **Introductory Offer → Create** → **Free Trial · 1 Week · New Subscribers · All Countries**.
3. **Review Information → upload paywall screenshot** (capture from an Xcode Run → tap "Upgrade").

That flips it from *Missing Metadata* → *Ready to Submit*.

---

## Subscription details (paste these)
- **Subscription Price:** United States **$9.99 / month** (pick the $9.99 tier; other territories auto-fill — adjust if you want).
- **Localization (English U.S.):**
  - **Display Name:** `Pulse Pro`
  - **Description:** `Unlock every AI feature: AI-built plans and pulses, the AI coach, meal and form analysis, and unlimited goals.`
- **Introductory Offer:** Type **Free Trial** · Duration **1 Week** · Eligibility **New Subscribers** · Territories **All**.
- **Family Sharing:** OFF.
- **Subscription Review Information:**
  - **Review screenshot:** the paywall screen (I'll attach a captured PNG from the smoke test).
  - **Review note (paste):**
    `Pulse Pro is a single auto-renewable subscription ($9.99/mo, 1-week free trial) that unlocks all AI features (AI-built plans/"pulses", AI coach chat, meal-photo and form analysis, unlimited AI goals). Free tier keeps unlimited manual goals. To test: tap any AI feature or "Upgrade" to reach the paywall and subscribe via the sandbox account (no charge). AI responses are served by our Cloudflare Worker (pulse-ai-proxy) backed by Google Gemini.`

---

## App Privacy "nutrition label" — answers (match PrivacyInfo.xcprivacy exactly)
Data Collection = **Yes**. For every type below: **Linked to identity = Yes**, **Used for Tracking = No**, **Purpose = App Functionality**.
| Category | Type |
|---|---|
| Contact Info | **Email Address**, **Name** (Sign in with Apple) |
| Identifiers | **User ID** |
| User Content | **Photos or Videos** (meal/form/proof photos), **Other User Content** (goal text, coach chat) |

- Declare that user content + photos are **sent to a third party (Google LLC – Gemini API)** for AI processing, **not** sold/shared for advertising, **not** used for tracking.
- Do **NOT** declare Health/Fitness (HealthKit removed), Crash Data, or Product Interaction (no analytics SDK).

---

## Other version-page items (click-list)
- [ ] **Privacy Policy URL** + **Terms (EULA) URL** — enter the live GitHub Pages URLs (same as in-app). Support URL already implied: `https://shimondeitel.github.io/pulse-goals/`. Verify both load.
- [ ] **Age rating** questionnaire → results in **13+** (Terms set 13+; fitness content; always-on content filter).
- [ ] **Screenshots** (6.9" iPhone required; 6.5" optional) + **description**, **keywords**, **promotional text**.
- [ ] **Attach the subscription** to the 1.0 version (Version → In-App Purchases/Subscriptions → select `com.shimondeitel.pulse.pro.monthly`) so it's reviewed with the build.
- [ ] **Export compliance:** nothing to answer — `ITSAppUsesNonExemptEncryption=false` is already in Info.plist.

---

## 🔴 BLOCKER #2 — Paid Apps Agreement (the #1 cause of "product unavailable")
- **Business → Agreements, Tax, and Banking** → **Paid Applications** must show **Active**, with **bank account** + **tax forms** complete.
- Until this is Active, `Product.products(for:)` returns nothing in production even if the subscription exists → paywall shows "Pulse Pro isn't available to purchase yet."
- ⚠️ I cannot fill banking/tax for you — please confirm this shows **Active**.

---

## CloudKit (do before TestFlight/App Store, not local)
- CloudKit Dashboard → container `iCloud.com.shimondeitel.pulsegoals` → **Deploy Schema Changes…** (Development → Production). Production starts empty; without this, sync silently falls to local-only on real builds.
