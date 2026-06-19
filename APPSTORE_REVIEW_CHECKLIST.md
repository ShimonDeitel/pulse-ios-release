# Pulse — App Store Review Readiness Checklist

App: **Pulse Goals** · Bundle `com.shimondeitel.pulse` · v**1.0** (build **2**) · iOS **18.0**+
Last reviewed: 2026-06-01 (after HealthKit removal + workout-library prune)

Legend: ✅ handled in the build · ⚠️ decide/do before App Store submit · 🔧 App Store Connect / Xcode step (not code)

---

## ✅ Already handled in the build (verified in source)

| Apple guideline | Status | Evidence |
|---|---|---|
| **2.1 Completeness / no broken features / no crashes** | ✅ | App builds + launches + runs on device and simulator. Half-built HealthKit removed; workout library pruned to only exercises the camera can actually track → no "feature doesn't work" surfaces. |
| **3.1.1 In-App Purchase for digital content** | ✅ (see ⚠️1) | Pro AI features sit behind StoreKit 2 auto-renewable `com.shimondeitel.pulse.pro.monthly` ($9.99/mo). No external/3rd-party payment path. |
| **3.1.2 Subscriptions** | ✅ | Paywall shows price, monthly duration, included features, **Restore Purchases** (top-right), and **Terms (EULA)** + **Privacy Policy** links (in-app views + live website links). |
| **5.1.1(v) Account deletion** | ✅ | In-app "Delete account" (Profile → Privacy) → `destroyAllUserDataForAccountDeletion()` wipes Core Data, App-Group store, UserDefaults, local notifications, and propagates deletes to the user's private CloudKit DB. |
| **5.1.1 / 5.1.2 Data & privacy** | ✅ | `PrivacyInfo.xcprivacy` declares collected types (Email, Name, UserID, Photos/Videos, OtherUserContent), `NSPrivacyTracking=false`. Only required-reason API used is UserDefaults (`CA92.1`) — declared. In-app + website Privacy Policy. |
| **Permission usage strings match real features** | ✅ | Camera ("track your form and count reps… processed on your device and never recorded or uploaded"), Face ID (reveal saved password), Photo Library add/use (proof + milestone photos). **No unused permission strings.** |
| **Entitlements match features** | ✅ | Sign in with Apple, iCloud/CloudKit, Push, App Groups. **HealthKit entitlement correctly ABSENT** now that the feature is removed (entitlement/feature parity — a common reject cause, avoided). |
| **No hardcoded secrets** | ✅ | No `sk-`/API keys in the binary. All AI routed through the server proxy; any dev key lives in Keychain only. |
| **4.0 / 4.8 Sign in with Apple** | ✅ | Apple is the primary auth; native flow. |
| **Encryption / export compliance** | ✅ | `ITSAppUsesNonExemptEncryption = false` (standard HTTPS only) → no export-compliance prompt/docs. |
| **Health/fitness + AI-accuracy disclaimers** | ✅ | Terms §4 (AI output is informational, not professional advice) + §7 (health/fitness "not a medical device" disclaimer) + `GoalRealityCheckView` shown before goal creation. Important now that fitness is a core feature. |
| **Debug-only affordances gated out of production** | ✅ (see ⚠️1) | Skip-auth is `#if targetEnvironment(simulator)` only; cert-pinning relaxed only in `#if DEBUG`; redeem button gated by `isTestFlightOrDebug`. |

---

## ⚠️ Decide / do BEFORE App Store submission

1. **Redeem-code button (3.1.1) — the one real review risk.**
   It's shown when `AppConfig.isTestFlightOrDebug` is true = (`#if DEBUG`) **OR** (App Store **sandbox** receipt). Effect:
   - Hidden for paying App Store users ✅
   - **Visible to App Review** (they run a sandbox receipt) and to TestFlight testers.
   Apple can read "enter a code to unlock Pro" as bypassing IAP. Keep it for TestFlight now, but **before the public App Store build choose one**:
   - **(a) Safest:** change the gate to `#if DEBUG` only → the button is gone from the Release/review build; reviewers test Pro via **sandbox IAP (free during review)**.
   - **(b)** Leave it and add an App Review note explaining it's a receipt-gated internal test tool, unreachable by production users. (Relies on reviewer discretion.)
   Also: the 5 codes are compiled into the Release binary (extractable via `strings`). For a zero-footprint release, wrap `validRedeemCodes` + `redeemPro(...)` in `#if DEBUG` too.

2. **Reviewer access to Pro.** Since Pro needs a purchase, confirm the StoreKit subscription is **"Ready to Submit"** and attached to the version so the reviewer can subscribe in the **sandbox (free)**. (Don't rely on the redeem code for review if you pick option (a) above.)

3. **AI proxy must be live + funded.** The app's AI depends on the server proxy. A down/empty proxy = AI features fail = **2.1** rejection. Verify `/v1/session`, `/v1/chat`, `/v1/budget` respond and the global pot has balance before submitting.

---

## 🔧 Operational steps (App Store Connect / Xcode — not code)

- [ ] Create auto-renewable subscription `com.shimondeitel.pulse.pro.monthly` ($9.99) in ASC; complete **Paid Apps Agreement** + banking + tax; attach to the version.
- [ ] Fill the **App Privacy "nutrition label"** to match `PrivacyInfo.xcprivacy` (Email, Name, User ID, Photos, User Content; **no tracking**).
- [ ] Add **Privacy Policy URL** + **Terms/EULA URL** in ASC (live GitHub Pages — verify both load).
- [ ] **Deploy CloudKit schema to Production** (CloudKit Console → Deploy Schema). Dev schema does **not** serve TestFlight/App Store (Production) users.
- [ ] **Distribution signing:** prior archive was *Development*-signed. In Xcode Organizer → Distribute App → App Store Connect, let Xcode create the **Apple Distribution** cert + App Store provisioning. Confirm `aps-environment = production` in the exported build.
- [ ] Age rating questionnaire (note the always-on 13+ content filter + fitness content).
- [ ] Screenshots (6.9"/6.5"), description, keywords, support URL, marketing URL.

---

## Notes (won't block review)
- Dead cert-pinning placeholder (`CertificatePinning.swift` — empty pins, delegate unused). Harmless; remove for cleanliness when convenient.
