import SwiftUI
import StoreKit

// MARK: - Upgrade / Paywall (CloudDesign: dark bg, comparison grid, social proof)

struct UpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    // Single paid plan now — Pro is the only tier you can buy.
    private let selectedTier: SubscriptionTier = .pro
    // Real StoreKit 2 purchase engine — the only thing that can unlock Pro.
    @State private var store = StoreManager.shared
    @State private var showError = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    /// Per-Apple-ID intro-offer eligibility. nil = not yet checked (optimistic:
    /// keep showing the trial); false = this Apple ID already used the intro
    /// offer, so we must NOT advertise the free trial (Apple 3.1.2 accuracy).
    @State private var introEligible: Bool? = nil

    var body: some View {
        ZStack {
            // Dark background
            Color(red: 0.04, green: 0.04, blue: 0.03).ignoresSafeArea()

            // Subtle radial glow
            RadialGradient(
                colors: [PulseColors.signal.opacity(0.15), Color.clear],
                center: .init(x: 0.5, y: 0.2),
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Top bar: Close ──────────────────
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                    // Restore Purchases — REQUIRED by Apple 3.1.1 for any app with
                    // an auto-renewable subscription. Top-right, per request.
                    Button {
                        PulseHaptics.light()
                        Task {
                            // Drive the same verified StoreKit engine the purchase
                            // path uses, then observe the result instead of
                            // fire-and-forgetting. Mirror the purchase branch.
                            await store.restore()
                            if store.isPro {
                                PulseHaptics.success()
                                appState.showWelcomeToPro = true
                                dismiss()
                            } else {
                                PulseHaptics.error()
                                // Only blame a "different Apple ID" when the sync
                                // actually succeeded and simply found no entitlement.
                                // If AppStore.sync itself failed (network hiccup,
                                // server error, or the user cancelled the sign-in),
                                // show a generic try-again message instead.
                                store.lastErrorMessage = store.lastRestoreFailed
                                    ? "Couldn't reach the App Store to restore your purchases. Check your connection and try again."
                                    : "We didn't find an active subscription on this Apple ID. If it expired or you subscribed with a different Apple ID, that's why — sign in with that account, or subscribe to continue."
                                showError = true
                            }
                        }
                    } label: {
                        Text("Restore")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(height: 44)
                    }
                    .disabled(store.phase != .idle)
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.top, 4)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // ── Hero ──────────────────────────────────
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 8) {
                                MiniPulseView(width: 42, height: 18)
                                Text("PULSE PRO")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .tracking(11 * 0.16)
                                    .foregroundColor(PulseColors.signal)
                            }
                            .padding(.bottom, 18)

                            VStack(alignment: .leading, spacing: 0) {
                                Text("A chat.")
                                    .font(.system(size: 44, weight: .semibold))
                                    .tracking(-1.76)
                                    .foregroundColor(.white)
                                Text("A plan.")
                                    .font(.system(size: 44, weight: .semibold))
                                    .tracking(-1.76)
                                    .foregroundColor(.white)
                                Text("A pulse.")
                                    .font(.system(size: 44, weight: .semibold))
                                    .tracking(-1.76)
                                    .foregroundColor(PulseColors.signal)
                            }
                            .padding(.bottom, 16)

                            Text("Free gives you the full AI coach and one goal. Pro unlocks unlimited goals and Primary Access — priority AI that never makes you wait.")
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.6))
                                .lineSpacing(15 * 0.5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PulseSpacing.screenEdge)
                        .padding(.bottom, 28)

                        // ── Comparison grid ────────────────────────
                        HStack(spacing: 1) {
                            // Free column
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("FREE")
                                        .font(PulseTypography.eyebrow)
                                        .eyebrowTracking()
                                        .foregroundColor(.white.opacity(0.5))
                                    Text("$0")
                                        .font(.system(size: 28, weight: .semibold))
                                        .tracking(-1.12)
                                        .foregroundColor(.white)
                                }

                                comparisonRow("Full AI coach + plans", on: true, dark: true)
                                comparisonRow("Scan meals for nutrition", on: true, dark: true)
                                comparisonRow("AI form coach + live reps", on: true, dark: true)
                                comparisonRow("AI chat", on: true, dark: true)
                                comparisonRow("Unlimited goals", on: false, dark: true)
                                comparisonRow("Primary Access — no waiting", on: false, dark: true)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(red: 0.06, green: 0.06, blue: 0.05))

                            // Pro column
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("PRO")
                                        .font(PulseTypography.eyebrow)
                                        .eyebrowTracking()
                                        .foregroundColor(.white.opacity(0.7))
                                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                                        Text(store.displayPrice)
                                            .font(.system(size: 28, weight: .semibold))
                                            .tracking(-1.12)
                                        Text("/\(store.billingPeriodText)")
                                            .font(.system(size: 14))
                                            .opacity(0.7)
                                    }
                                    .foregroundColor(.white)
                                    // Keep price + period on one line, scaling to
                                    // fit the narrow column so no digit wraps or
                                    // sits "out of line".
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    // Redact the price until the live product loads, so
                                    // we never flash the hardcoded fallback (or the wrong
                                    // currency to a non-USD user) before StoreKit resolves.
                                    .redacted(reason: productReady ? [] : .placeholder)
                                }

                                comparisonRow("Full AI coach + plans", on: true, dark: false)
                                comparisonRow("Scan meals for nutrition", on: true, dark: false)
                                comparisonRow("AI form coach + live reps", on: true, dark: false)
                                comparisonRow("AI chat", on: true, dark: false)
                                comparisonRow("Unlimited goals", on: true, dark: false)
                                comparisonRow("Primary Access — no waiting", on: true, dark: false)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PulseColors.signal)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, PulseSpacing.screenEdge)
                        .padding(.bottom, 24)

                        // ── AI feature showcase (so people know these exist) ──
                        VStack(alignment: .leading, spacing: 14) {
                            Text("WHAT THE AI DOES FOR YOU")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(1.4)
                                .foregroundColor(PulseColors.signal)
                            aiFeature("camera.viewfinder", "Scan any meal",
                                      "Snap a photo and get instant calories + macros, logged automatically.")
                            aiFeature("brain.head.profile", "Remembers your nutrition",
                                      "It learns what you eat, tracks your day, and builds you a meal plan.")
                            aiFeature("figure.strengthtraining.traditional", "Live form coach",
                                      "Your camera counts every rep and corrects your form in real time.")
                            aiFeature("sparkles", "AI builds the whole plan",
                                      "From one photo it writes your workouts, meals, and daily pulses.")
                            aiFeature("bubble.left.and.text.bubble.right.fill", "A chat that knows you",
                                      "An AI chat that tracks your streak and pushes you in your style.")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, PulseSpacing.screenEdge)
                        .padding(.bottom, 24)

                        Text(freeTrialOffer != nil
                             ? "Free for \(trialDurationText), then \(store.displayPrice)/\(store.billingPeriodText), billed to your Apple ID. Auto-renews unless cancelled at least 24 hours before the period ends. Cancel anytime."
                             : "\(store.displayPrice)/\(store.billingPeriodText), billed to your Apple ID. Auto-renews unless turned off at least 24 hours before the period ends. Cancel anytime.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .padding(.top, 18)
                            .padding(.horizontal, PulseSpacing.screenEdge)
                    }
                    .padding(.bottom, 16)
                }

                // ── CTA buttons ────────────────────────────────
                VStack(spacing: 8) {
                    Button {
                        Task {
                            // Not loaded yet (still loading, the IAP isn't live, or
                            // we're offline): retry the load and surface the reason —
                            // never run purchase() against a nil product.
                            guard productReady else {
                                await store.loadProducts()
                                if store.proProduct == nil, store.lastErrorMessage != nil {
                                    PulseHaptics.error(); showError = true
                                }
                                return
                            }
                            let ok = await store.purchase()
                            if ok { PulseHaptics.success(); appState.showWelcomeToPro = true; dismiss() }
                            else if store.lastErrorMessage != nil { PulseHaptics.error(); showError = true }
                        }
                    } label: {
                        ZStack {
                            if store.phase == .purchasing {
                                ProgressView().tint(.white)
                            } else if !productReady {
                                // Live price not loaded yet. Spinner while loading; a
                                // retry affordance if it failed — so we never flash a
                                // hardcoded "Subscribe — $9.99" or strand the user on a
                                // dead button when the product isn't sellable yet.
                                if store.lastErrorMessage != nil {
                                    Text("Try again")
                                        .font(.system(size: 15, weight: .semibold))
                                        .tracking(-0.15)
                                        .foregroundColor(.white)
                                } else {
                                    ProgressView().tint(.white)
                                }
                            } else {
                                // Apple 3.1.2: if the product has an introductory
                                // free trial, the trial must be disclosed BEFORE
                                // purchase — so the CTA leads with it.
                                Text(freeTrialOffer != nil
                                     ? "Start \(trialDurationText) free trial"
                                     : "Subscribe — \(store.displayPrice)/\(store.billingPeriodText)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .tracking(-0.15)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(PulseColors.signal)
                        .clipShape(RoundedRectangle(cornerRadius: 9999, style: .continuous))
                    }
                    // Non-tappable while a purchase/restore is in flight, AND while
                    // the live price is still loading (a plain product load keeps
                    // phase == .idle, so the spinner would otherwise be a tappable
                    // silent no-op). Stays tappable in the "Try again" error state.
                    .disabled(store.phase != .idle || (!productReady && store.lastErrorMessage == nil))

                    Button { dismiss() } label: {
                        Text("Stay on free")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .disabled(store.phase != .idle)

                    #if DEBUG
                    // DEBUG-ONLY developer unlock — compiled out of Release,
                    // TestFlight, and the App Store. Lets the owner test Pro/AI on
                    // local builds without a real purchase. Shipping builds remain
                    // purchase-only (a verified StoreKit purchase is the sole path).
                    Button {
                        SubscriptionManager.shared.debugTogglePro()
                        PulseHaptics.success()
                        if SubscriptionManager.shared.currentTier == .pro { appState.showWelcomeToPro = true }
                        dismiss()
                    } label: {
                        Text("DEBUG: \(SubscriptionManager.shared.currentTier == .pro ? "Lock" : "Unlock") Pro (testing only)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.yellow)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    #endif

                    // (Restore Purchases moved to the top-right of this screen.)

                    // Terms of Use + Privacy Policy — REQUIRED on the subscription
                    // screen (Apple 3.1.2). Open the in-app legal views so they
                    // always load (never 404).
                    HStack(spacing: 8) {
                        Button { showTerms = true } label: {
                            Text("Terms of Use").underline()
                        }
                        Text("·").opacity(0.5)
                        Button { showPrivacy = true } label: {
                            Text("Privacy Policy").underline()
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.top, 2)
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.bottom, 18)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await store.loadProducts()
            // Check whether THIS Apple ID is still eligible for the intro offer;
            // a returning user who already used the trial is not, so don't
            // advertise it to them.
            if let sub = store.proProduct?.subscription {
                introEligible = await sub.isEligibleForIntroOffer
            }
        }
        .alert("Purchase", isPresented: $showError) {
            Button("OK") { store.lastErrorMessage = nil }
        } message: {
            Text(store.lastErrorMessage ?? "Something went wrong. Please try again.")
        }
        // Terms of Use + Privacy Policy — in-app legal views (always load).
        .sheet(isPresented: $showTerms) {
            NavigationStack {
                TermsOfServiceView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showTerms = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showPrivacy = false }
                        }
                    }
            }
        }
    }

    /// True once StoreKit has returned the live product. Until then the paywall
    /// must not flash a hardcoded price or a CTA whose label/price changes on
    /// load — it shows redacted placeholders / a loading (or retry) CTA instead.
    private var productReady: Bool { store.proProduct != nil }

    // MARK: - Introductory free trial (Apple 3.1.2 disclosure)

    /// The product's introductory offer ONLY when it is a genuine free trial.
    /// A pay-as-you-go / pay-up-front intro offer is a discount, not a free
    /// trial, so we must not advertise it as one. nil → no trial to disclose.
    private var freeTrialOffer: Product.SubscriptionOffer? {
        // Hide the trial only when this Apple ID is DEFINITIVELY ineligible
        // (introEligible == false); nil/true keep showing it so eligible users
        // on a slow eligibility check aren't under-served.
        guard introEligible != false,
              let offer = store.proProduct?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return offer
    }

    /// Human-readable trial length, e.g. "7-day" for a P1W offer. Reads the live
    /// offer period; falls back to "7-day" (Pulse.storekit's configured length)
    /// if the period is missing/unexpected.
    private var trialDurationText: String {
        guard let period = freeTrialOffer?.period else { return "7-day" }
        let n = period.value
        switch period.unit {
        case .day:   return "\(n)-day"
        case .week:  return "\(n * 7)-day"
        case .month: return n == 1 ? "1-month" : "\(n)-month"
        case .year:  return n == 1 ? "1-year" : "\(n)-year"
        @unknown default: return "7-day"
        }
    }

    // MARK: - Components

    /// One AI-feature showcase row: icon + name + one-line description.
    private func aiFeature(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(PulseColors.signal)
                .frame(width: 30, height: 30)
                .background(PulseColors.signal.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 12.5))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func comparisonRow(_ text: String, on: Bool, dark: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        on
                            ? (dark ? PulseColors.signal : .white.opacity(0.95))
                            : Color.clear
                    )
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(
                                on ? Color.clear : (dark ? .white.opacity(0.2) : .white.opacity(0.35)),
                                lineWidth: 1
                            )
                    )

                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(dark ? .white : PulseColors.signal)
                }
            }

            Text(text)
                .font(.system(size: 13.5))
                .foregroundColor(
                    dark
                        ? (on ? .white : .white.opacity(0.35))
                        : .white
                )
                .strikethrough(!on, color: dark ? .white.opacity(0.35) : .white.opacity(0.5))
        }
    }

}
