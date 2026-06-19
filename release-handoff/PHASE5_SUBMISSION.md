# PHASE 5 — Submit for Review (fill-in-the-blanks)

Once the build is on TestFlight and processed, attach it to the **1.0** version and fill these. Everything is pre-written — you should only need to paste and tap **Submit for Review**.

## Export compliance
- Already handled in Info.plist (`ITSAppUsesNonExemptEncryption=false`). If asked: **uses encryption = Yes**, **qualifies for exemption = Yes** (standard HTTPS/TLS).

## Age rating
- Questionnaire → **13+** (fitness content + AI; always-on content filter). No objectionable content.

## App Review Information → Notes (paste)
```
Pulse is an AI goal/fitness coach. Sign-in: standard Sign in with Apple — reviewers can use any Apple ID (the simulator/dev build auto-skips auth; the App Store build requires Apple sign-in).

PRO / IN-APP PURCHASE: One auto-renewable subscription, com.shimondeitel.pulse.pro.monthly ($9.99/mo, 1-week free trial), unlocks all AI features. To test: tap any AI feature (AI coach, "Build with AI" goal, meal/form photo analysis) or the "Upgrade" button to reach the paywall, then subscribe with the sandbox account (no charge during review). Free tier keeps UNLIMITED manual goals.

AI BACKEND: AI responses are served by our Cloudflare Worker proxy (pulse-ai-proxy) backed by Google Gemini. No third-party login required. The app ships no provider API keys.

ACCOUNT DELETION (5.1.1(v)): Profile → Privacy → Delete Account fully erases all local + iCloud data. The app runs no token-holding backend server, so there is no server-side Apple token to revoke; deletion removes 100% of the user's data.

PRIVACY: Goal text, coach-chat, and any photos the user submits are sent transiently to Google LLC (Gemini API) for AI processing only — not retained on our servers, never sold or used for tracking or advertising.
```

## Demo account
- Not required (Sign in with Apple, reviewer's own Apple ID). Pro is reachable via sandbox IAP — no special account needed. If ASC forces a demo login field, note "Sign in with Apple — no username/password required."

## Final pre-submit checklist
- [ ] Build (1.0 / 2) attached to the version
- [ ] Subscription `com.shimondeitel.pulse.pro.monthly` attached + **Ready to Submit** (PHASE 3)
- [ ] Paid Apps Agreement **Active** (PHASE 3 blocker #2)
- [ ] App Privacy answers match `PrivacyInfo.xcprivacy` (PHASE 3)
- [ ] Privacy Policy + Terms URLs entered and loading
- [ ] Screenshots uploaded (6.9")
- [ ] CloudKit schema deployed to **Production** (PHASE 3)
- [ ] **Tap Submit for Review** ← the only thing left
