# PHASE 4 — Archive, sign & upload to TestFlight

> Build from a **local copy** (`/tmp/pulse_build`, already has all fixes). Per gotcha #1, Xcode chokes on the Google Drive mount path — do NOT open the project from `…/CloudStorage/GoogleDrive…`. If you want a stable (non-/tmp) copy:
> `rsync -a --exclude .git --exclude node_modules "/tmp/pulse_build/" "$HOME/PulseBuild/"`

## Pre-flight (already verified by me)
- ✅ Debug + Release compile: **BUILD SUCCEEDED** (signing-free)
- ✅ Version 1.0, build **2** (app + widget + tests all CURRENT_PROJECT_VERSION = 2)
- ✅ `PULSE_PROXY_BASE_URL = https://pulse-ai-proxy.s0533495227.workers.dev` (Debug+Release) and **backend /health is live (HTTP 200)** → archive ships with proxy AI ON
- ✅ `ITSAppUsesNonExemptEncryption=false` → no export-compliance prompt
- ✅ Groq bridge is `#if DEBUG` only → **no provider key in the Release binary**

## 🔒 NEEDS YOU — Apple sign-in / 2FA (one-time portal setup, runbook §A)
In **developer.apple.com → Identifiers**, confirm these exist under team **W7Q885Q59C**:
1. App Group `group.com.shimondeitel.pulsegoals`
2. iCloud container `iCloud.com.shimondeitel.pulsegoals`
3. App ID `com.shimondeitel.pulse` → capabilities: **Sign In with Apple**, **iCloud (CloudKit)** → that container, **App Groups** → that group. (Do NOT add HealthKit — removed.)
4. App ID `com.shimondeitel.pulse.widgets` → **App Groups** only.
5. A valid **Apple Distribution** certificate (Xcode → Settings → Accounts → Manage Certificates can create it).

## Archive — RECOMMENDED (Xcode Organizer)
1. Open `/tmp/pulse_build/pulse.xcodeproj` in Xcode (signed into the W7Q885Q59C account).
2. Target `pulse` → Signing & Capabilities → "Automatically manage signing", Team = W7Q885Q59C. Repeat for `PulseWidgetExtension`.
3. Destination → **Any iOS Device (arm64)** → **Product → Archive**.
4. Organizer → **Validate App** (App Store Connect, automatic signing, upload symbols = Yes) → fix anything → **Distribute App → App Store Connect → Upload**.
5. Build appears under **TestFlight** as "Processing" (minutes–1 hr).

## Archive — CLI alternative (needs `-allowProvisioningUpdates` → triggers 2FA)
```bash
cd /tmp/pulse_build
xcodebuild -project pulse.xcodeproj -scheme pulse -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/pulse_build/build/Pulse.xcarchive \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=W7Q885Q59C \
  clean archive

xcodebuild -exportArchive \
  -archivePath /tmp/pulse_build/build/Pulse.xcarchive \
  -exportOptionsPlist /tmp/pw/ExportOptions.plist \
  -exportPath /tmp/pulse_build/build/export \
  -allowProvisioningUpdates
# then upload the .ipa via Organizer, or altool with an App Store Connect API key
```
`ExportOptions.plist` is ready at `/tmp/pw/ExportOptions.plist` (method app-store-connect, team W7Q885Q59C, automatic, uploadSymbols).

## ⚠️ RELEASE-GATE checks before you hit Distribute
- Scheme **StoreKit Configuration = None** for the Release/Archive run (gotcha #3 — `Pulse.storekit` is sim-only; leaving it selected breaks live IAP). The shared scheme's archive action already uses Release.
- Every subsequent upload must **bump `CURRENT_PROJECT_VERSION`** (app + widget together): `xcrun agvtool new-version -all 3`.
