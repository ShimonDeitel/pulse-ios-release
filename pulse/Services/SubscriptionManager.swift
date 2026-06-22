import SwiftUI
import CoreData

// MARK: - Tier model
// 2 tiers:
//   • Free — AI is free (routes to free-provider waterfall). 1 active goal. F badge.
//   • Pro  — $9.99/mo, the single paid plan. Unlimited goals + Primary Access
//            (priority AI). $2.50/user/mo AI budget. P badge.

enum SubscriptionTier: String, CaseIterable {
    case free, pro

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro:  return "Pulse Pro"
        }
    }

    var price: String {
        switch self {
        case .free: return "Free"
        case .pro:  return "$9.99/mo"
        }
    }

    /// Letter / symbol shown next to display name (F, P, ✓).
    var badgeText: String {
        switch self {
        case .free: return "F"
        case .pro:  return "P"
        }
    }

    /// SF Symbol for the badge icon style.
    var badgeIcon: String {
        switch self {
        case .free: return "circle"
        case .pro:  return "circle.fill"
        }
    }

    var maxGoals: Int {
        switch self {
        case .free: return 1
        case .pro:  return .max
        }
    }

    /// Monthly AI budget cap (USD) of DeepSeek V4 usage. Free routes to free
    /// background providers (no paid-provider cost to us), so the 0.50 figure below
    /// is only the dev/no-proxy device-side fallback — with the proxy on, free
    /// traffic uses free keys and never draws from a paid pot.
    /// Pro = the single $9.99 plan: $9.99 − ~$3 Apple cut ≈ $7; $3.00 to AI leaves
    /// ~$4 margin. This is a MONTHLY budget, paced across the month: the proxy
    /// unlocks it ~1/daysInMonth per day with carry-forward (unspent days roll
    /// onto the remaining days), and surfaces "Usage limit hit — resets tomorrow"
    /// when today's accrued slice is spent.
    /// NOTE: in production the AUTHORITATIVE cap is the server-side AI proxy
    /// (PER_USER_CAP_USD). DailyAIBudget is only the device-side fallback used in
    /// dev/direct-key mode; with the proxy enabled the server is the source of truth.
    var monthlyAIBudgetUSD: Double {
        switch self {
        // Free routes to free background models (no provider cost to us). The
        // small device-side figure only matters in dev/no-proxy mode; with the
        // proxy on, the server is authoritative and free traffic uses free keys.
        case .free: return 0.50
        case .pro:  return 3.00
        }
    }

    /// Whether this tier can use AI to generate plans / pulses / roadmaps.
    /// AI is now FREE for everyone — free users route through free background
    /// models; Pro adds unlimited goals + Primary Access (priority, no waiting).
    var hasAIGeneration: Bool { true }

    var features: [SubscriptionFeature] {
        switch self {
        case .free:
            return [
                SubscriptionFeature(icon: "wand.and.stars", text: "AI-built plans, pulses & coach", included: true),
                SubscriptionFeature(icon: "camera.viewfinder", text: "Scan meals for macros", included: true),
                SubscriptionFeature(icon: "target", text: "1 active goal", included: true),
                SubscriptionFeature(icon: "infinity", text: "Unlimited goals", included: false),
                SubscriptionFeature(icon: "bolt.fill", text: "Primary Access — priority AI, no waiting", included: false),
            ]
        case .pro:
            return [
                SubscriptionFeature(icon: "infinity", text: "Unlimited goals", included: true),
                SubscriptionFeature(icon: "bolt.fill", text: "Primary Access — priority AI, never wait in line", included: true),
                SubscriptionFeature(icon: "wand.and.stars", text: "AI-built plans, pulses & coach", included: true),
                SubscriptionFeature(icon: "checkmark.seal.fill", text: "Verified Pro badge", included: true),
            ]
        }
    }
}

struct SubscriptionFeature: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let included: Bool
}

// MARK: - SubscriptionManager
//
// The app-wide, UI-facing projection of the user's subscription. It is a PURE
// READ MODEL: the only writer of `currentTier` is `applyEntitlement(...)`, which
// `StoreManager` calls after StoreKit has cryptographically verified a current
// entitlement. There is intentionally NO local "upgrade"/"cancel" that flips
// state — Pro can only be unlocked by a real, Apple-verified purchase, and only
// Apple can cancel it. On a cold launch this starts on Free and StoreKit
// reconciles within a moment (fail-closed: AI stays gated until verified Pro).
//
// All AI gating reads `currentTier` / `hasAIGeneration`, so "payment unlocks the
// AI" is automatic, and a refund / lapse / revocation re-locks it automatically.
@Observable
class SubscriptionManager {
    static let shared = SubscriptionManager()

    var currentTier: SubscriptionTier = .free
    /// Whether the subscription will charge again. Mirrors Apple's renewal state.
    var autoRenew: Bool = true
    /// True while the introductory free trial is active (no charge yet).
    var isOnTrial: Bool = false
    var startDate: Date? = nil
    var trialEndDate: Date? = nil
    /// The next renewal date (also the access-end date once cancelled). Comes
    /// straight from the verified StoreKit transaction's expiration date.
    var nextBillingDate: Date? = nil

    var isPro: Bool { currentTier == .pro }
    /// AI is free for everyone (always true). Pro adds unlimited goals + Primary
    /// Access (priority AI); AI itself is not a paid feature.
    var hasAIGeneration: Bool { currentTier.hasAIGeneration }
    /// Subscribed but auto-renew turned off — access until the period ends.
    var isCancelled: Bool { isPro && !autoRenew }

    /// When paid access ends if not renewed: trial end while trialing, else next billing.
    var accessEndsDate: Date? { isOnTrial ? trialEndDate : nextBillingDate }

    private init() {}

    #if DEBUG
    // Developer-only Pro unlock for LOCAL testing (simulator + Debug builds).
    // Compiled OUT of Release, TestFlight, and the App Store entirely — in any
    // shipping build the ONLY path to Pro is a verified StoreKit purchase. This
    // is a pure #if DEBUG flag (no receipt/runtime gating), so it cannot leak.
    private static let debugProKey = "pulse_debug_pro_unlock"
    var isDebugProUnlocked: Bool { UserDefaults.standard.bool(forKey: Self.debugProKey) }
    @MainActor func debugTogglePro() {
        let on = !isDebugProUnlocked
        UserDefaults.standard.set(on, forKey: Self.debugProKey)
        currentTier = on ? .pro : .free
        if on {
            autoRenew = true; isOnTrial = false; if startDate == nil { startDate = Date() }
        } else {
            // Mirror applyEntitlement's downgrade reset so toggling Pro→Free in
            // testing doesn't leave stale renewal/trial state (a phantom billing date).
            autoRenew = true; isOnTrial = false
            startDate = nil; trialEndDate = nil; nextBillingDate = nil
        }
    }
    #endif

    /// The SINGLE entry point that mutates entitlement state. Called by
    /// `StoreManager` after Apple verifies (or revokes) the subscription.
    @MainActor
    func applyEntitlement(isPro: Bool, expiration: Date?, willAutoRenew: Bool, isInTrial: Bool) {
        #if DEBUG
        // Honor the dev unlock so the launch/foreground reconciliation can't
        // flip a test session back to Free. (Release: this is compiled out.)
        if isDebugProUnlocked { currentTier = .pro; return }
        #endif
        currentTier = isPro ? .pro : .free
        guard isPro else {
            autoRenew = true
            isOnTrial = false
            startDate = nil
            trialEndDate = nil
            nextBillingDate = nil
            return
        }
        autoRenew = willAutoRenew
        isOnTrial = isInTrial
        if startDate == nil { startDate = Date() }
        // Expiration is the renewal date; while trialing it's also the trial end.
        nextBillingDate = expiration
        trialEndDate = isInTrial ? expiration : nil
    }

    /// SILENT launch-time reconciliation. Touching `StoreManager.shared` starts
    /// its transaction listener + first entitlement resolution; we then re-read
    /// the latest VERIFIED entitlement via `Transaction.currentEntitlements`,
    /// which never prompts for an Apple Account. Safe to call on every launch.
    ///
    /// This deliberately does NOT call `AppStore.sync()` — that forces an Apple
    /// Account sign-in prompt and, per Apple's guidance, must only run from an
    /// explicit user "Restore Purchases" tap (see `restore()` below).
    func bootstrap() {
        #if DEBUG
        if isDebugProUnlocked { Task { @MainActor in self.currentTier = .pro }; return }
        #endif
        Task { @MainActor in await StoreManager.shared.refreshEntitlements() }
    }

    /// EXPLICIT, user-initiated restore (the "Restore Purchases" button). This
    /// calls `AppStore.sync()`, which can prompt for the Apple Account — which is
    /// exactly why it must never run automatically at launch.
    func restore() {
        Task { @MainActor in await StoreManager.shared.restore() }
    }

    func canCreateGoal(currentCount: Int) -> Bool {
        if isPro { return true }
        return currentCount < currentTier.maxGoals
    }

    /// Number of currently-active goals in `context`. Treats a nil/empty status as
    /// active (matching `Goal.statusEnum`'s coercion) so the cap can't be bypassed
    /// by legacy rows. Mirrors the count used in `GoalInputViewModel.saveGoal`.
    func activeGoalCount(in context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<Goal>(entityName: "Goal")
        request.predicate = NSPredicate(
            format: "status == %@ OR status == %@ OR status == nil",
            GoalStatus.active.rawValue, ""
        )
        return (try? context.count(for: request)) ?? 0
    }

    /// Authoritative save-site backstop shared by every goal-creation view: Pro is
    /// unlimited; Free is capped at one active goal. Returns false when a Free user
    /// is already at the cap, so the caller presents the paywall instead of
    /// creating another active goal. (AI is free for everyone — this gates only
    /// the goal COUNT.)
    func canCreateGoal(in context: NSManagedObjectContext) -> Bool {
        canCreateGoal(currentCount: activeGoalCount(in: context))
    }
}
