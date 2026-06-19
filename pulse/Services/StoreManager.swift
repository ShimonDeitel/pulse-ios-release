import Foundation
import StoreKit
import UIKit

// MARK: - StoreManager (StoreKit 2)
//
// The SOLE source of truth for the Pulse Pro entitlement.
//
// Security model — matches the "Apple-grade, no extractable keys" bar:
//   • No secrets in the binary. Apple holds the receipt; StoreKit verifies every
//     transaction's signature on-device. We trust ONLY `.verified` results.
//   • Pro unlocks exclusively from a CURRENT, VERIFIED entitlement for the
//     auto-renewable product — never from a local flag a tampered build could
//     flip. On launch we fail CLOSED (Free) until StoreKit confirms.
//   • The server AI proxy independently meters each Apple-authenticated user, so
//     even a jailbroken client that forced the gate open can't exceed the budget.
//
// The Pro tier keys off `SubscriptionManager.currentTier`, which this engine is
// the only writer of (via `applyEntitlement`). AI itself is FREE for everyone;
// Pro's value is unlimited goals + Primary Access (priority AI). So Pro's perks
// follow automatically the moment Apple confirms the purchase — and revert the
// moment the entitlement lapses, is refunded, or is revoked.
@MainActor
@Observable
final class StoreManager {
    static let shared = StoreManager()

    /// The single auto-renewable subscription product id (App Store Connect).
    static let proProductID = "com.shimondeitel.pulse.pro.monthly"

    /// Loaded product (nil until `loadProducts` succeeds). Drives localized price.
    private(set) var proProduct: Product?

    /// True only while a current, verified Pro entitlement exists.
    private(set) var isPro = false

    /// Verified entitlement details, surfaced in the subscription UI.
    private(set) var expirationDate: Date?
    private(set) var willAutoRenew = true
    private(set) var isInTrialPeriod = false

    /// Whether StoreKit has finished its first entitlement resolution. Until then
    /// the UI shows a neutral loading state instead of flashing "Free".
    private(set) var hasResolvedEntitlements = false

    /// Paywall UI state.
    enum Phase: Equatable { case idle, purchasing, restoring }
    var phase: Phase = .idle
    var lastErrorMessage: String?

    /// True when the most recent `restore()` failed to even reach the App Store
    /// (AppStore.sync threw / was cancelled), as opposed to syncing cleanly and
    /// simply finding no entitlement. Lets the paywall distinguish "couldn't
    /// reach the App Store" from "you have nothing to restore on this Apple ID".
    private(set) var lastRestoreFailed = false

    /// Localized price string for the current storefront, e.g. "$10" / "£9.99".
    /// ALWAYS a preformatted String — StoreKit's localized `displayPrice` or a
    /// clean literal fallback (never a raw Double, which would render "10.0").
    /// We strip a trailing zero-cents suffix so a whole-dollar plan reads "$10"
    /// not "$10.00"; a price with real cents like "$9.99" is left untouched.
    /// Avoids the cramped, misaligned trailing "0" in the narrow Pro column.
    var displayPrice: String {
        let raw = proProduct?.displayPrice ?? "$9.99"
        // Strip ONLY a trailing zero-cents suffix ("$10.00" -> "$10"), anchored to
        // the END via regex. A global replace mangled localized prices that use
        // "." or "," as a thousands separator, e.g. IDR "Rp 159.000" -> "Rp 1590".
        return raw.replacingOccurrences(of: "[.,]00$", with: "", options: .regularExpression)
    }

    /// Localized "/period" suffix, e.g. "month". Empty until loaded.
    var billingPeriodText: String {
        guard let unit = proProduct?.subscription?.subscriptionPeriod.unit else { return "month" }
        switch unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "month"
        }
    }

    private var updatesTask: Task<Void, Never>?

    private init() {
        // Start the transaction listener IMMEDIATELY so renewals, refunds,
        // Ask-to-Buy approvals, and cross-device purchases are caught even when
        // they land before any paywall UI is on screen.
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }
    // No deinit: this is a process-lifetime singleton, so the transaction
    // listener must run for the whole app session. (A @MainActor deinit is also
    // nonisolated and can't touch `updatesTask`.)

    // MARK: - Verification

    /// Unwrap a StoreKit result, trusting ONLY cryptographically verified payloads.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: LocalizedError {
        case failedVerification
        case productUnavailable

        var errorDescription: String? {
            switch self {
            case .failedVerification:
                return "This purchase couldn't be verified by Apple. You have not been charged."
            case .productUnavailable:
                return "Pulse Pro isn't available to purchase yet. The subscription has to be live in App Store Connect — created with a price, and the Paid Applications Agreement Active — before Apple will sell it. If it was just set up, give it a few hours and try again."
            }
        }
    }

    // MARK: - Products

    func loadProducts() async {
        // Retry transient failures. A StoreKit product load can briefly fail on
        // a cold network or right after launch; a single silent failure used to
        // leave the paywall's button stuck on "unavailable" until the view was
        // rebuilt. Up to 3 attempts with backoff, and we clear the error on
        // success so the CTA recovers on its own.
        for attempt in 0..<3 {
            do {
                let products = try await Product.products(for: [Self.proProductID])
                if let p = products.first(where: { $0.id == Self.proProductID }) {
                    proProduct = p
                    lastErrorMessage = nil
                    return
                }
                // Empty result = the IAP isn't live in App Store Connect yet.
                // Retrying won't help, so surface the actionable message and stop.
                lastErrorMessage = StoreError.productUnavailable.errorDescription
                return
            } catch {
                lastErrorMessage = "Couldn't load subscription details. Check your connection and try again."
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s backoff
                }
            }
        }
    }

    // MARK: - Purchase

    /// Buy Pulse Pro. Returns true only once a verified entitlement is granted.
    @discardableResult
    func purchase() async -> Bool {
        guard phase == .idle else { return false }
        if proProduct == nil { await loadProducts() }
        guard let product = proProduct else {
            lastErrorMessage = StoreError.productUnavailable.errorDescription
            return false
        }
        lastErrorMessage = nil
        phase = .purchasing
        defer { phase = .idle }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                // Trust only Apple-verified transactions. A spoofed/unsigned
                // payload throws here and never unlocks Pro.
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isPro
            case .userCancelled:
                return false
            case .pending:
                // Ask-to-Buy / Strong Customer Authentication — the entitlement
                // arrives later through the Transaction.updates listener.
                lastErrorMessage = "Your purchase is pending approval. Pulse Pro unlocks automatically once it's approved."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Restore

    /// Restore purchases. StoreKit 2 syncs entitlements automatically, but an
    /// explicit restore satisfies App Review and recovers rare edge cases.
    func restore() async {
        guard phase == .idle else { return }
        phase = .restoring
        defer { phase = .idle }
        // Capture (don't swallow) the sync outcome so the paywall can tell a
        // transient/cancelled sync apart from a clean "no entitlement" result and
        // avoid wrongly blaming a "different Apple ID" for a network/cancel error.
        do {
            try await AppStore.sync()
            lastRestoreFailed = false
        } catch {
            lastRestoreFailed = true
        }
        await refreshEntitlements()
    }

    // MARK: - Entitlement resolution (the only writer of Pro state)

    func refreshEntitlements() async {
        var entitled = false
        var exp: Date?

        // currentEntitlements returns the user's active, non-revoked purchases,
        // each individually signature-verified by StoreKit.
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard transaction.productID == Self.proProductID else { continue }
            if transaction.revocationDate != nil { continue }                 // refunded / revoked
            if let e = transaction.expirationDate, e < Date() { continue }     // lapsed
            entitled = true
            exp = transaction.expirationDate
        }

        isPro = entitled
        expirationDate = exp
        await refreshRenewalState()
        hasResolvedEntitlements = true

        // Project onto the app-wide UI/gating model. This is what flips AI on/off.
        SubscriptionManager.shared.applyEntitlement(
            isPro: entitled,
            expiration: exp,
            willAutoRenew: willAutoRenew,
            isInTrial: isInTrialPeriod
        )
    }

    /// Pull auto-renew + trial status from the subscription group's status.
    private func refreshRenewalState() async {
        guard isPro, let sub = proProduct?.subscription else {
            willAutoRenew = true
            isInTrialPeriod = false
            return
        }
        let statuses = (try? await sub.status) ?? []
        for status in statuses {
            guard let renewal = try? checkVerified(status.renewalInfo),
                  let transaction = try? checkVerified(status.transaction),
                  transaction.productID == Self.proProductID else { continue }
            willAutoRenew = renewal.willAutoRenew
            // Only treat the period as a free trial when the intro offer is a
            // GENUINE free trial. An introductory offer can also be pay-as-you-go
            // or pay-up-front (a paid discount, not a trial); those must NOT drive
            // the "no charge yet" trial UI. Mirrors UpgradeView.freeTrialOffer.
            isInTrialPeriod = (transaction.offer?.type == .introductory
                               && transaction.offer?.paymentMode == .freeTrial)
            return
        }
        // Entitled but no matching status row — assume renewing, not trialing.
        willAutoRenew = true
        isInTrialPeriod = false
    }

    // MARK: - Transaction listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { break }   // singleton deallocated → stop listening
                guard let transaction = try? self.checkVerified(update) else { continue }
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }

    // MARK: - Manage / cancel (Apple-hosted)

    /// Apple does not permit programmatic cancellation. Present the system
    /// manage-subscriptions sheet where the user cancels, resumes, or changes
    /// the plan; refresh entitlements when they return.
    func showManageSubscriptions() async {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first

        guard let scene else {
            // No usable window scene — go straight to the subscriptions page.
            // Don't refresh here: UIApplication.open returns the instant the URL is
            // handed to the system (the app backgrounds), BEFORE the user can act.
            // The scenePhase==.active foreground hook (App/PulseApp.swift) re-runs
            // refreshEntitlements when they return, which is the only correct moment
            // — a cancellation (auto-renew off) emits no Transaction.updates event.
            await openAppleSubscriptionsPage()
            return
        }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
            // The native sheet's call returns only after the user dismisses it, so
            // any change they made is already reflected — refresh now.
            await refreshEntitlements()
        } catch {
            // The native sheet is unavailable in this environment (Simulator, a
            // dev/debug build with no real subscription, or StoreKit testing) and
            // would otherwise just spin. Fall back to Apple's account subscriptions
            // page so "Cancel subscription" ALWAYS lands somewhere it can be done.
            // No refresh here: UIApplication.open returns before the user acts, so
            // the foreground (scenePhase==.active) hook in App/PulseApp.swift picks
            // up the change when they come back.
            await openAppleSubscriptionsPage()
        }
    }

    /// Reliable fallback for managing / cancelling a subscription: Apple's account
    /// subscriptions page (opens Settings ▸ Apple Account ▸ Subscriptions, or the
    /// App Store). Always available, even when the native sheet is not.
    @MainActor
    private func openAppleSubscriptionsPage() async {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            await UIApplication.shared.open(url)
        }
    }
}
