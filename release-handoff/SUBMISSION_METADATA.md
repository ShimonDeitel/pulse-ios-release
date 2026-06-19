# Pulse — App Store Connect submission metadata (paste-ready)

Bundle: `com.shimondeitel.pulse` · Team `W7Q885Q59C` (Joshua / yehoshua.deitel@gmail.com) · Version 1.0 (build 2)
Archive ready in Xcode Organizer: **Pulse 2026-06-14** (also `~/pulse_ios_archive/pulse.xcarchive`)

## App information
- **Name** (≤30): `Pulse: AI Goal Coach`
- **Subtitle** (≤30): `Goals, habits & AI coaching`
- **Primary category**: Health & Fitness  ·  **Secondary**: Productivity
- **Age rating**: 4+ (no objectionable content; questionnaire = all "None")

## URLs (live)
- **Privacy Policy**: https://pulse-app-79418.web.app/privacy
- **Support**: https://pulse-app-79418.web.app/support
- **Marketing**: https://pulse-app-79418.web.app

## Promotional text (≤170)
Turn any goal into a daily plan. Pulse breaks your goal into bite-size daily "pulses," tracks your streak, and keeps you moving with an AI coach in your corner.

## Keywords (≤100, comma-separated)
goal,habit,tracker,ai,coach,fitness,workout,streak,motivation,routine,planner,productivity,self care

## Description
Show up. Every day.

Pulse turns whatever you want to achieve — get fit, learn a skill, ship a project, build a habit — into a clear daily plan, then keeps you on it.

• AI roadmaps — tell Pulse your goal and it breaks it into small daily "pulses" you can actually finish.
• Streaks & momentum — check off today's pulse, keep your streak alive, watch progress add up.
• An AI coach in your corner — pick a mentor style and get nudges, check-ins, and answers when you're stuck.
• Built for real life — workouts, skills, projects, money goals, daily habits, challenges, and photo-based transformations.
• Private by design — your goals sync across your devices with iCloud. AI is free for everyone.

Pulse Pro ($9.99/month, 1-week free trial): unlimited goals plus Primary Access — priority AI whenever you need it. AI features themselves are free for all users.

Subscriptions auto-renew unless cancelled at least 24 hours before the period ends; manage or cancel anytime in your Apple ID settings. Terms: https://pulse-app-79418.web.app/terms · Privacy: https://pulse-app-79418.web.app/privacy

## What's New (1.0)
First release of Pulse. Set a goal, get an AI-built daily plan, keep your streak, and have a coach in your pocket.

## App Review notes
- No account required to try: tap "Skip" / Sign in with Apple for cross-device iCloud sync.
- AI runs through our server proxy. Free tier uses no-cost AI providers; Pulse Pro adds priority access. AI features need a network connection.
- In-app purchase: auto-renewable subscription `com.shimondeitel.pulse.pro.monthly` ($9.99/mo, 1-week trial) — unlocks unlimited goals + priority AI. Core app + AI are usable for free.
- No third-party login/secrets needed for review.

## Subscription (App Store Connect → Subscriptions)
- Reference Name: Pulse Pro Monthly
- Product ID: `com.shimondeitel.pulse.pro.monthly`
- Duration: 1 month · Price: $9.99 (Tier) · Intro offer: 1 week free trial
- Group: Pulse Pro
- Requires the **Paid Applications Agreement** active first (Joshua: banking + tax).

## Remaining human steps (Joshua's Apple account)
1. Accept Paid Applications Agreement (banking + tax) — gates the subscription + paid submission.
2. Upload the build: open the **Pulse 2026-06-14** archive in Xcode → Organizer → Distribute App → App Store Connect. (Or provide the API key **Issuer ID** so Claude uploads via the `AuthKey_SSJA634V44.p8` key.)
3. Create the app record + the subscription IAP above, attach build 2.
4. Paste the metadata above, add screenshots (6.7" + 6.5" + 5.5" iPhone), set age rating.
5. CloudKit Dashboard: promote schema Dev → Production (so sync works in the release).
6. Submit for Review.
